defmodule AshPlatform.Techtree.Provenance do
  @moduledoc false

  alias AshPlatform.Formation
  alias AshPlatform.Techtree.{EvidenceStateUpdate, Payload}

  @lineage_kinds ~w(
    derived_from
    supports
    contradicts
    reproduces
    fails_to_reproduce
    supersedes
  )
  @projection_statuses ~w(not_started pending submitted confirmed failed)

  @spec public_node_list_item(map()) :: map()
  def public_node_list_item(node) do
    node
    |> base_node()
    |> Map.merge(public_provenance(node, :not_checked))
    |> Map.put(:display_kind, Map.get(node, :display_kind))
    |> put_position(node)
  end

  @spec browser_node(map()) :: map()
  def browser_node(node) do
    node
    |> node_map()
    |> Map.merge(public_node_list_item(node))
  end

  @spec public_node(map(), list(), map()) :: map()
  def public_node(node, edges, verification) do
    node
    |> base_node()
    |> Map.merge(%{
      kind: Map.get(node, :kind) || Map.get(node, :display_kind),
      base_mainnet_projection: base_mainnet_projection(node),
      edges: Enum.map(edges, &public_edge/1)
    })
    |> Map.merge(public_provenance(node, verification))
    |> put_position(node)
    |> put_recorded(node, :lineage_node_ids)
    |> put_recorded(node, :capsule)
    |> put_recorded(node, :immutable_payloads)
    |> put_recorded(node, :evidence_projection)
    |> put_evidence_state(node)
  end

  @spec resolve_profile(map()) :: map() | nil
  def resolve_profile(node) do
    case Map.get(node, :publisher_regent_id) do
      nil ->
        nil

      regent_id ->
        case Formation.get_public_regent_by_id(regent_id, actor: nil) do
          {:ok, %{slug: slug}} when is_binary(slug) -> %{profile_url: "/regents/#{slug}"}
          _result -> nil
        end
    end
  rescue
    _error -> nil
  end

  defp base_node(node) do
    %{
      id: Map.get(node, :id),
      tree_id: Map.get(node, :tree_id),
      title: Map.get(node, :title),
      summary: Map.get(node, :summary),
      payload_hash: Map.get(node, :payload_hash),
      published_at: datetime(Map.get(node, :published_at))
    }
  end

  defp node_map(%{__struct__: _} = node), do: Map.from_struct(node)
  defp node_map(node) when is_map(node), do: node

  defp public_provenance(node, verification) do
    reference = Payload.reference(node)
    contributor_id = Map.get(node, :contributor_id)
    contributor_profile = resolve_profile(node)
    projection_status = projection_status(node)

    %{
      contributor: contributor(contributor_id, contributor_profile),
      lineage: lineage(node),
      manifest_cid: reference.cid,
      manifest_hash: reference.hash,
      manifest_uri: reference.uri,
      payload_url: reference.url,
      payload_verification: verification_payload(node, verification),
      projection_status: projection_status,
      published_at: datetime(Map.get(node, :published_at))
    }
    |> put_if_present(:contributor_id, contributor_id)
    |> put_inspect_evidence(node)
  end

  defp contributor(nil, _profile), do: nil

  defp contributor(agent_id, profile) when is_binary(agent_id) do
    %{agent_id: agent_id, profile_url: profile && profile.profile_url}
  end

  defp contributor(_agent_id, _profile), do: nil

  defp verification_payload(node, verification) do
    expected_hash = Map.get(node, :manifest_hash)

    case verification do
      %{status: status, expected_hash: expected, actual_hash: actual} ->
        %{status: status, expected_hash: expected || expected_hash, actual_hash: actual}

      :not_checked ->
        %{
          status:
            if(is_nil(Map.get(node, :manifest_cid)), do: :not_available, else: :not_checked),
          expected_hash: expected_hash,
          actual_hash: nil
        }

      _result ->
        %{status: :not_checked, expected_hash: expected_hash, actual_hash: nil}
    end
  end

  defp lineage(node) do
    case Map.get(node, :lineage) do
      value when is_map(value) ->
        value
        |> Enum.map(fn {node_id, kind} -> %{node_id: node_id, kind: kind} end)
        |> normalize_lineage()

      value when is_list(value) ->
        normalize_lineage(value)

      nil ->
        lineage_from_legacy(node)

      _value ->
        []
    end
  end

  defp lineage_from_legacy(node) do
    case Map.get(node, :lineage_node_ids) do
      node_ids when is_list(node_ids) ->
        Enum.map(node_ids, &%{node_id: &1, kind: "derived_from"})

      _value ->
        []
    end
  end

  defp normalize_lineage(references) do
    references
    |> Enum.map(&normalize_lineage_reference/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.node_id)
    |> Enum.sort_by(&{&1.kind, &1.node_id})
  end

  defp normalize_lineage_reference(%{node_id: node_id, kind: kind}),
    do: normalize_lineage_reference({node_id, kind})

  defp normalize_lineage_reference(%{"node_id" => node_id, "kind" => kind}),
    do: normalize_lineage_reference({node_id, kind})

  defp normalize_lineage_reference({node_id, kind})
       when is_binary(node_id) and kind in @lineage_kinds,
       do: %{node_id: node_id, kind: kind}

  defp normalize_lineage_reference({node_id, kind})
       when is_binary(node_id) and is_atom(kind) do
    kind = Atom.to_string(kind)
    if kind in @lineage_kinds, do: %{node_id: node_id, kind: kind}
  end

  defp normalize_lineage_reference(_reference), do: nil

  defp projection_status(node) do
    status = Map.get(node, :projection_status, :not_started)

    cond do
      is_atom(status) and Atom.to_string(status) in @projection_statuses -> Atom.to_string(status)
      is_binary(status) and status in @projection_statuses -> status
      true -> "not_started"
    end
  end

  defp base_mainnet_projection(node) do
    status = projection_status(node)

    %{
      chain_id: 8453,
      projection_status: status,
      record_uid: nil,
      transaction_hash: nil,
      block_number: nil
    }
  end

  defp put_inspect_evidence(payload, node) do
    case Map.get(node, :manifest_digest) do
      digest when is_binary(digest) ->
        Map.put(payload, :inspect_evidence, %{manifest_digest: digest})

      _value ->
        payload
    end
  end

  defp put_if_present(payload, _key, nil), do: payload
  defp put_if_present(payload, key, value), do: Map.put(payload, key, value)

  defp put_position(payload, %{pos_x: x, pos_y: y}) when not is_nil(x) and not is_nil(y),
    do: Map.put(payload, :position, %{x: x, y: y})

  defp put_position(payload, _node), do: payload

  defp put_recorded(payload, node, field) do
    case Map.fetch(node, field) do
      {:ok, value} when not is_nil(value) -> Map.put(payload, field, value)
      _missing_or_nil -> payload
    end
  end

  defp put_evidence_state(payload, node) do
    case Map.get(node, :id) do
      id when is_binary(id) ->
        case EvidenceStateUpdate.latest_for_node(id) do
          {:ok, nil} -> Map.put(payload, :evidence_state, synthesized_evidence_state(node))
          {:ok, update} -> Map.put(payload, :evidence_state, public_evidence_state(update))
          _error -> Map.put(payload, :evidence_state, synthesized_evidence_state(node))
        end

      _id ->
        put_recorded(payload, node, :evidence_state)
    end
  rescue
    _error -> put_recorded(payload, node, :evidence_state)
  end

  defp synthesized_evidence_state(node) do
    %{
      status: "issued",
      evidence_reference_ids: [],
      updated_at: datetime(Map.get(node, :published_at))
    }
  end

  defp public_evidence_state(%EvidenceStateUpdate{} = update) do
    %{
      status: Atom.to_string(update.status),
      reason: update.reason,
      evidence_reference_ids: update.evidence_reference_ids,
      updated_at: datetime(update.inserted_at)
    }
  end

  defp public_edge(edge) do
    %{
      from_node_id: edge.from_node_id,
      to_node_id: edge.to_node_id,
      kind: edge.kind
    }
  end

  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp datetime(value) when is_binary(value), do: value
  defp datetime(_value), do: nil
end
