defmodule AshPlatformWeb.TechtreePublicationController do
  use AshPlatformWeb, :controller

  alias AshPlatform.AgentAuth.{AgentIdentity, ClaimRateLimiter}
  alias AshPlatform.Techtree.{Publication, PublicationInput, PublicationReceipt}

  @kinds %{
    "environment_family" => :environment_family,
    "benchmark_slice" => :benchmark_slice,
    "uplift_report" => :uplift_report,
    "reproduction" => :reproduction,
    "audit" => :audit
  }
  @digest_pattern ~r/\A[0-9a-f]{64}\z/
  @lineage_kinds %{
    "derived_from" => "derived_from",
    "supports" => "supports",
    "contradicts" => "contradicts",
    "reproduces" => "reproduces",
    "fails_to_reproduce" => "fails_to_reproduce",
    "supersedes" => "supersedes"
  }

  def create(%Plug.Conn{query_string: ""} = conn, params) do
    case validate(params) do
      {:ok, attributes} -> publish(conn, attributes)
      {:error, :invalid_input} -> invalid_input(conn)
    end
  end

  def create(conn, _params), do: invalid_input(conn)

  defp publish(conn, attributes) do
    actor = conn.assigns.agent_identity

    case Publication.accepted_replay(attributes, actor) do
      {:ok, node} ->
        render_published(conn, node, true)

      :not_found ->
        create_new(conn, attributes, actor)

      {:error, :temporarily_unavailable} ->
        error(conn, :service_unavailable, :temporarily_unavailable)
    end
  end

  defp create_new(conn, attributes, actor) do
    with :ok <- admit_publication(actor),
         {:ok, node, replayed} <-
           Publication.publish(attributes, actor, conn.assigns.verified_siwa_envelope) do
      render_published(conn, node, replayed)
    else
      {:error, :conflict} ->
        error(conn, :conflict, :conflict)

      {:error, :forbidden} ->
        error(conn, :forbidden, :forbidden)

      {:error, :rate_limited} ->
        replay_or_rate_limit(conn, attributes, actor)

      {:error, :invalid_input} ->
        error(conn, :bad_request, :invalid_input)

      {:error, _reason} ->
        error(conn, :service_unavailable, :temporarily_unavailable)
    end
  end

  defp replay_or_rate_limit(conn, attributes, actor) do
    case Publication.accepted_replay(attributes, actor) do
      {:ok, node} ->
        render_published(conn, node, true)

      :not_found ->
        error(conn, :too_many_requests, :rate_limited)

      {:error, :temporarily_unavailable} ->
        error(conn, :service_unavailable, :temporarily_unavailable)
    end
  end

  defp render_published(conn, node, replayed) do
    status = if replayed, do: :ok, else: :created

    conn
    |> put_status(status)
    |> json(%{data: PublicationReceipt.published(node, replayed)})
  end

  defp invalid_input(conn) do
    case admit_publication(conn.assigns.agent_identity) do
      :ok -> error(conn, :bad_request, :invalid_input)
      {:error, :rate_limited} -> error(conn, :too_many_requests, :rate_limited)
    end
  end

  defp admit_publication(%AgentIdentity{registry_address: registry_address, token_id: token_id}) do
    config = Application.fetch_env!(:ash_platform, :techtree_publication_rate_limit)

    ClaimRateLimiter.admit(
      {:publication, registry_address, token_id},
      Keyword.fetch!(config, :limit),
      Keyword.fetch!(config, :window_seconds)
    )
  end

  defp validate(params) do
    with {:ok, params} <- PublicationInput.normalize(params),
         {:ok, regent_id} <- uuid(params["regent_id"]),
         {:ok, tree_id} <- uuid(params["tree_id"]),
         {:ok, kind} <- kind(params["kind"]),
         {:ok, title} <- string(params["title"], 1, 200),
         {:ok, summary} <- optional_string(params["summary"], 2_000),
         {:ok, payload_hash} <- optional_string(params["payload_hash"], 128),
         {:ok, idempotency_key} <- string(params["idempotency_key"], 1, 255),
         {:ok, manifest_digest} <- digest(params["manifest_digest"]),
         {:ok, manifest_cid} <- optional_string(params["manifest_cid"], 255),
         {:ok, manifest_hash} <- optional_digest(params["manifest_hash"]),
         {:ok, manifest_uri} <- optional_manifest_uri(params["manifest_uri"]),
         {:ok, lineage} <- lineage(params["lineage"]),
         :ok <-
           validate_manifest_reference(manifest_cid, manifest_hash, manifest_uri, manifest_digest) do
      {:ok,
       %{
         regent_id: regent_id,
         tree_id: tree_id,
         kind: kind,
         title: title,
         summary: summary,
         payload_hash: payload_hash,
         idempotency_key: idempotency_key,
         manifest_digest: manifest_digest,
         manifest_cid: manifest_cid,
         manifest_hash: manifest_hash,
         manifest_uri: manifest_uri,
         lineage: lineage
       }}
    end
  end

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_input}
    end
  end

  defp kind(value) do
    case Map.fetch(@kinds, value) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, :invalid_input}
    end
  end

  defp string(value, minimum, maximum) when is_binary(value) do
    if String.valid?(value) do
      length = String.length(value)

      if length >= minimum and length <= maximum,
        do: {:ok, value},
        else: {:error, :invalid_input}
    else
      {:error, :invalid_input}
    end
  end

  defp string(_value, _minimum, _maximum), do: {:error, :invalid_input}

  defp optional_string(nil, _maximum), do: {:ok, nil}
  defp optional_string(value, maximum), do: string(value, 0, maximum)

  defp digest(value) when is_binary(value) do
    if Regex.match?(@digest_pattern, value),
      do: {:ok, value},
      else: {:error, :invalid_input}
  end

  defp digest(_value), do: {:error, :invalid_input}

  defp optional_digest(nil), do: {:ok, nil}
  defp optional_digest(value), do: digest(value)

  defp optional_manifest_uri(nil), do: {:ok, nil}

  defp optional_manifest_uri(value) do
    with {:ok, value} <- string(value, 1, 2_048),
         %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil} <-
           URI.parse(value),
         true <- scheme in ["https", "ipfs"] and is_binary(host) do
      {:ok, value}
    else
      _result -> {:error, :invalid_input}
    end
  end

  defp lineage(nil), do: {:ok, %{}}

  defp lineage(%{"node_id" => _node_id, "kind" => _kind} = value),
    do: lineage([value])

  defp lineage(%{node_id: _node_id, kind: _kind} = value),
    do: lineage([value])

  defp lineage(value) when is_map(value) do
    value
    |> Enum.map(fn {node_id, kind} -> %{"node_id" => node_id, "kind" => kind} end)
    |> lineage()
  end

  defp lineage(value) when is_list(value) do
    with {:ok, references} <- Enum.reduce_while(value, {:ok, []}, &lineage_reference/2),
         true <- unique_node_ids?(references) do
      {:ok, Map.new(references, fn %{node_id: node_id, kind: kind} -> {node_id, kind} end)}
    else
      _result -> {:error, :invalid_input}
    end
  end

  defp lineage(_value), do: {:error, :invalid_input}

  defp lineage_reference(reference, {:ok, references}) when is_map(reference) do
    node_id = Map.get(reference, "node_id", Map.get(reference, :node_id))
    kind = Map.get(reference, "kind", Map.get(reference, :kind))

    with :ok <- allow_lineage_reference_keys(reference),
         {:ok, node_id} <- uuid(node_id),
         {:ok, kind} <- lineage_kind(kind) do
      {:cont, {:ok, [%{node_id: node_id, kind: kind} | references]}}
    else
      _result -> {:halt, {:error, :invalid_input}}
    end
  end

  defp lineage_reference(_reference, _acc), do: {:halt, {:error, :invalid_input}}

  defp allow_lineage_reference_keys(reference) do
    case Enum.sort(Map.keys(reference)) do
      ["kind", "node_id"] -> :ok
      [:kind, :node_id] -> :ok
      _keys -> {:error, :invalid_input}
    end
  end

  defp lineage_kind(value) do
    case Map.fetch(@lineage_kinds, value) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, :invalid_input}
    end
  end

  defp unique_node_ids?(references) do
    node_ids = Enum.map(references, & &1.node_id)
    length(node_ids) == length(Enum.uniq(node_ids))
  end

  defp validate_manifest_reference(nil, nil, nil, _manifest_digest), do: :ok

  defp validate_manifest_reference(manifest_cid, manifest_hash, manifest_uri, manifest_digest)
       when is_binary(manifest_cid) and is_binary(manifest_hash) do
    if manifest_hash == manifest_digest and (is_nil(manifest_uri) or is_binary(manifest_uri)),
      do: :ok,
      else: {:error, :invalid_input}
  end

  defp validate_manifest_reference(
         _manifest_cid,
         _manifest_hash,
         _manifest_uri,
         _manifest_digest
       ),
       do: {:error, :invalid_input}

  defp error(conn, status, code) do
    idempotency_key =
      case conn.body_params do
        %{"idempotency_key" => value} when is_binary(value) -> value
        _params -> nil
      end

    conn
    |> put_status(status)
    |> json(%{
      error: %{code: code, message: message(code)},
      receipt: PublicationReceipt.failed(code, idempotency_key)
    })
  end

  defp message(:conflict),
    do: "The idempotency key was already used for a different publication."

  defp message(:forbidden),
    do: "The verified agent is not paired with the requested Regent."

  defp message(:rate_limited), do: "Too many publications. Please wait and try again."

  defp message(:invalid_input), do: "The publication request is invalid."

  defp message(:temporarily_unavailable),
    do: "The publication could not be completed at this time."
end
