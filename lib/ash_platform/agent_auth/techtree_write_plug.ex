defmodule AshPlatform.AgentAuth.TechtreeWritePlug do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias AshPlatform.AgentAuth.{AgentIdentity, VerificationClient}
  alias AshPlatform.Techtree.Checks.PublisherOwnsNode
  alias AshPlatform.Techtree.PublicationReceipt

  @session_cookie "_ash_platform_key="

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with :ok <- exclude_privy(conn),
         {:ok, body} <- raw_body(conn),
         envelope = envelope(conn, body),
         {:ok, identity} <- verify(envelope),
         {:ok, actor} <- paired_actor(identity),
         :ok <- admit_regent(conn.body_params, actor),
         :ok <- admit_target(conn, actor) do
      conn
      |> assign(:agent_identity, actor)
      |> assign(:verified_siwa_envelope, envelope)
    else
      {:error, :payload_too_large} ->
        halt_error(conn, 413, :payload_too_large)

      {:error, :invalid_input} ->
        halt_error(conn, 400, :invalid_request)

      {:error, :unauthorized} ->
        halt_error(conn, 401, :unauthorized)

      {:error, :forbidden} ->
        halt_error(conn, 403, :forbidden)

      {:error, :not_found} ->
        halt_error(conn, 404, :not_found)

      {:error, :temporarily_unavailable} ->
        halt_error(conn, 503, :temporarily_unavailable)
    end
  end

  defp exclude_privy(conn) do
    cookie? = Enum.any?(get_req_header(conn, "cookie"), &String.contains?(&1, @session_cookie))

    bearer? =
      Enum.any?(get_req_header(conn, "authorization"), fn value ->
        value |> String.downcase() |> String.starts_with?("bearer ")
      end)

    if cookie? or bearer?, do: {:error, :unauthorized}, else: :ok
  end

  defp raw_body(%{assigns: %{verified_envelope_body_error: :too_large}}),
    do: {:error, :payload_too_large}

  defp raw_body(%{assigns: %{verified_envelope_raw_body: body}}) when is_binary(body),
    do: {:ok, body}

  defp raw_body(_conn), do: {:error, :invalid_input}

  defp envelope(conn, body) do
    %{
      method: conn.method,
      path: conn.request_path,
      headers: Map.new(conn.req_headers),
      body: body
    }
  end

  defp verify(envelope) do
    case VerificationClient.verify(envelope) do
      {:ok, identity} -> {:ok, identity}
      {:error, :verification_unavailable} -> {:error, :temporarily_unavailable}
      {:error, :not_configured} -> {:error, :temporarily_unavailable}
      {:error, _reason} -> {:error, :unauthorized}
    end
  rescue
    _error -> {:error, :temporarily_unavailable}
  catch
    _kind, _reason -> {:error, :temporarily_unavailable}
  end

  defp paired_actor(identity) do
    params = [identity.agent_id, identity.registry_address, identity.token_id, identity.wallet]

    case Ecto.Adapters.SQL.query(
           AshPlatform.Repo,
           """
           SELECT id::text, regent_id::text
           FROM agent_links
           WHERE agent_id = $1
             AND registry_address = $2
             AND token_id = $3
             AND wallet = $4
           LIMIT 1
           """,
           params
         ) do
      {:ok, %{rows: [[agent_link_id, regent_id]]}} ->
        audience = Application.fetch_env!(:ash_platform, :siwa) |> Keyword.fetch!(:audience)

        {:ok,
         struct!(
           AgentIdentity,
           Map.merge(identity, %{
             regent_id: regent_id,
             agent_link_id: agent_link_id,
             audience: audience,
             chain_id: 8453
           })
         )}

      {:ok, %{rows: []}} ->
        {:error, :forbidden}

      {:error, _error} ->
        {:error, :temporarily_unavailable}
    end
  rescue
    _error -> {:error, :temporarily_unavailable}
  end

  defp admit_regent(%{"regent_id" => requested}, %AgentIdentity{regent_id: paired}) do
    case Ecto.UUID.cast(requested) do
      {:ok, ^paired} -> :ok
      {:ok, _other} -> {:error, :forbidden}
      :error -> :ok
    end
  end

  defp admit_regent(_params, _actor), do: :ok

  defp admit_target(conn, actor) do
    case target_id(conn) do
      nil ->
        :ok

      {:ok, node_id} ->
        with :ok <- public_target(node_id),
             true <- PublisherOwnsNode.authorized?(actor, node_id) do
          :ok
        else
          false -> {:error, :forbidden}
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, :invalid_input}
    end
  end

  defp target_id(%{path_info: ["api", "techtree", "v1", "nodes", id, surface]})
       when surface in ["evidence-state", "notebook-artifact"] do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> :error
    end
  end

  defp target_id(_conn), do: nil

  defp public_target(node_id) do
    case Ecto.Adapters.SQL.query(
           AshPlatform.Repo,
           """
           SELECT 1
           FROM techtree.nodes
           WHERE id = $1
             AND workflow_state = 'published'
             AND published_at IS NOT NULL
           """,
           [Ecto.UUID.dump!(node_id)]
         ) do
      {:ok, %{rows: [[1]]}} -> :ok
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, _error} -> {:error, :temporarily_unavailable}
    end
  rescue
    _error -> {:error, :temporarily_unavailable}
  end

  defp halt_error(conn, status, code) do
    if agent_write_endpoint?(conn) do
      halt_agent_write_error(conn, status, code)
    else
      {publication_status, publication_code} =
        case code do
          :invalid_request -> {status, :invalid_input}
          :payload_too_large -> {400, :invalid_input}
          code -> {status, code}
        end

      halt_publication_error(conn, publication_status, publication_code)
    end
  end

  defp halt_agent_write_error(conn, status, code) do
    body = %{error: %{code: code, message: agent_write_message(code)}}

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code(status), Jason.encode!(body))
    |> halt()
  end

  defp halt_publication_error(conn, status, code) do
    idempotency_key =
      case conn.body_params do
        %{"idempotency_key" => value} when is_binary(value) -> value
        _params -> nil
      end

    body = %{
      error: %{code: code, message: message(code)},
      receipt: PublicationReceipt.failed(code, idempotency_key)
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code(status), Jason.encode!(body))
    |> halt()
  end

  defp status_code(status) when is_integer(status), do: status
  defp status_code(status), do: Plug.Conn.Status.code(status)

  defp agent_write_endpoint?(%{path_info: ["api", "techtree", "v1", "nodes", _id, surface]})
       when surface in ["evidence-state", "notebook-artifact"],
       do: true

  defp agent_write_endpoint?(_conn), do: false

  defp agent_write_message(:invalid_request), do: "The agent write request is invalid."
  defp agent_write_message(:unauthorized), do: "The signed agent request could not be verified."
  defp agent_write_message(:forbidden), do: "The verified agent is not the node publisher."
  defp agent_write_message(:not_found), do: "The requested public node was not found."
  defp agent_write_message(:payload_too_large), do: "The signed request body is too large."

  defp agent_write_message(:temporarily_unavailable),
    do: "The agent write could not be completed at this time."

  defp agent_write_message(_code), do: "The agent write request is invalid."

  defp message(:unauthorized), do: "The signed agent request could not be verified."
  defp message(:forbidden), do: "The verified agent is not paired with the requested Regent."
  defp message(:invalid_input), do: "The publication request is invalid."

  defp message(:temporarily_unavailable),
    do: "Signed-agent verification is temporarily unavailable."
end
