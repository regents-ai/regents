defmodule AshPlatform.Techtree.EvidenceStateUpdateTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation, Techtree}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.AgentAuth.AgentIdentity
  alias AshPlatform.Techtree.{EvidenceStateUpdate, Node, Provenance}

  @registry "0x1111111111111111111111111111111111111111"
  @wallet "0x2222222222222222222222222222222222222222"

  setup do
    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!(
        "did:privy:techtree-evidence-state:#{unique}",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    human = %Human{human_account_id: account.id}

    regent =
      Formation.form_regent!("evidence-state-#{unique}", "Evidence state #{unique}", actor: human)

    identity = %{
      agent_id: "agent-evidence-state-#{unique}",
      registry_address: @registry,
      token_id: Integer.to_string(unique),
      wallet: @wallet
    }

    issued = Formation.issue_agent_pairing_code!(regent.id, actor: human)
    link = Formation.claim_agent_link!(regent.id, issued.code, identity, actor: %System{})
    :ok = Techtree.ensure_seed_trees(actor: %System{})
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    %{identity: identity, link: link, regent: regent, tree: tree}
  end

  test "append stores the complete verified submitter and envelope shape", context do
    node = publish_node(context, "complete-shape")
    before_columns = node_columns(node)
    actor = agent_actor(context)
    envelope = %{"method" => "POST", "path" => "/evidence-state", "body" => "{}"}

    assert {:ok, update} =
             Techtree.append_evidence_state_update(
               node.id,
               :reproduced,
               "Reproduced from the submitted artifact.",
               [],
               envelope,
               actor: actor
             )

    assert update.node_id == node.id
    assert update.status == :reproduced
    assert update.reason == "Reproduced from the submitted artifact."
    assert update.evidence_reference_ids == []
    assert update.submitter_agent_id == actor.agent_id
    assert update.submitter_registry_address == actor.registry_address
    assert update.submitter_token_id == actor.token_id
    assert update.submitter_wallet == actor.wallet
    assert update.submitter_chain_id == actor.chain_id
    assert update.submitter_regent_id == actor.regent_id
    assert update.siwa_envelope == envelope
    assert %DateTime{} = update.inserted_at

    assert {:ok, [stored]} = EvidenceStateUpdate.all_for_node(node.id)
    assert stored.id == update.id

    assert node_columns(Ash.get!(Node, node.id, authorize?: false)) == before_columns
  end

  test "latest evidence state is derived from the append log and ties use descending ids",
       context do
    node = publish_node(context, "latest-order")
    actor = agent_actor(context)

    assert {:ok, nil} = EvidenceStateUpdate.latest_for_node(node.id)

    public = Provenance.public_node(node, [], :not_checked)

    assert public.evidence_state == %{
             status: "issued",
             evidence_reference_ids: [],
             updated_at: DateTime.to_iso8601(node.published_at)
           }

    assert {:ok, first} =
             Techtree.append_evidence_state_update(
               node.id,
               :reproduced,
               "first",
               [],
               %{"sequence" => 1},
               actor: actor
             )

    first_node_columns = node_columns(Ash.get!(Node, node.id, authorize?: false))
    first_row_columns = update_columns(first)

    assert {:ok, second} =
             Techtree.append_evidence_state_update(
               node.id,
               :disputed,
               "second",
               [],
               %{"sequence" => 2},
               actor: actor
             )

    assert {:ok, appended_rows} = EvidenceStateUpdate.all_for_node(node.id)
    assert update_columns(Enum.find(appended_rows, &(&1.id == first.id))) == first_row_columns

    tied_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    for update <- [first, second] do
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        "UPDATE techtree.evidence_state_updates SET inserted_at = $1 WHERE id = $2",
        [tied_at, Ecto.UUID.dump!(update.id)]
      )
    end

    assert {:ok, latest} = EvidenceStateUpdate.latest_for_node(node.id)
    assert {:ok, all} = EvidenceStateUpdate.all_for_node(node.id)
    assert latest.id == Enum.max([first.id, second.id])
    assert Enum.map(all, & &1.id) == Enum.sort([first.id, second.id], :desc)
    assert node_columns(Ash.get!(Node, node.id, authorize?: false)) == first_node_columns

    public = Provenance.public_node(node, [], :not_checked)

    assert public.evidence_state.status == Atom.to_string(latest.status)
    assert public.evidence_state.reason == latest.reason
    assert public.evidence_state.evidence_reference_ids == []
    assert public.evidence_state.updated_at == DateTime.to_iso8601(tied_at)
  end

  test "a latest-history lookup failure never fabricates issued after an invalidated append",
       context do
    node = publish_node(context, "history-failure")
    actor = agent_actor(context)

    assert {:ok, update} =
             Techtree.append_evidence_state_update(
               node.id,
               :invalidated,
               "Invalidated by the verified publisher.",
               [],
               %{"body" => "invalidated"},
               actor: actor
             )

    assert {:ok, [stored]} = EvidenceStateUpdate.all_for_node(node.id)
    assert stored.id == update.id

    Ecto.Adapters.SQL.query!(AshPlatform.Repo, "DROP TABLE techtree.evidence_state_updates")

    response = get(build_conn(), "/api/techtree/v1/nodes/#{node.id}")

    assert response.status == 503
    assert json_response(response, 503)["error"]["code"] == "temporarily_unavailable"
    refute response.resp_body =~ "issued"
  end

  test "target and reference nodes are locked and references must be public", context do
    node = publish_node(context, "reference-target")

    reference =
      Techtree.import_public_node!(context.tree.id, "Public reference", nil, nil,
        actor: %System{}
      )

    draft = draft_node(context, "private-reference")
    actor = agent_actor(context)

    assert {:ok, update} =
             Techtree.append_evidence_state_update(
               node.id,
               :reproduced,
               nil,
               [reference.id],
               %{"body" => "verified"},
               actor: actor
             )

    assert update.evidence_reference_ids == [reference.id]

    assert {:error, error} =
             Techtree.append_evidence_state_update(
               node.id,
               :disputed,
               nil,
               [draft.id],
               %{"body" => "rejected"},
               actor: actor
             )

    assert Exception.message(error) =~ "invalid_evidence_reference"
    assert {:ok, [latest]} = EvidenceStateUpdate.all_for_node(node.id)
    assert latest.id == update.id

    assert {:error, error} =
             Techtree.append_evidence_state_update(
               node.id,
               :expired,
               nil,
               [node.id],
               %{"body" => "self-reference"},
               actor: actor
             )

    assert Exception.message(error) =~ "invalid_evidence_reference"
    assert {:ok, [only_update]} = EvidenceStateUpdate.all_for_node(node.id)
    assert only_update.id == update.id

    assert {:error, error} =
             Techtree.append_evidence_state_update(
               node.id,
               :expired,
               nil,
               [Ash.UUID.generate()],
               %{"body" => "missing-reference"},
               actor: actor
             )

    assert Exception.message(error) =~ "invalid_evidence_reference"
    assert {:ok, [still_only_update]} = EvidenceStateUpdate.all_for_node(node.id)
    assert still_only_update.id == update.id
  end

  test "ownership requires the current link and the complete publisher tuple", context do
    node = publish_node(context, "ownership")
    actor = agent_actor(context)

    for forged <- [
          %{actor | agent_link_id: Ash.UUID.generate()},
          %{actor | agent_id: "different-agent"},
          %{actor | registry_address: "0x3333333333333333333333333333333333333333"},
          %{actor | token_id: "different-token"},
          %{actor | wallet: "0x3333333333333333333333333333333333333333"},
          %{actor | regent_id: Ash.UUID.generate()}
        ] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Techtree.append_evidence_state_update(
                 node.id,
                 :reproduced,
                 nil,
                 [],
                 %{"body" => "forged"},
                 actor: forged
               )
    end

    assert {:ok, _update} =
             Techtree.append_evidence_state_update(
               node.id,
               :reproduced,
               nil,
               [],
               %{"body" => "authorized"},
               actor: actor
             )
  end

  test "append is the only write action and cannot mutate an existing row" do
    actions = Ash.Resource.Info.actions(EvidenceStateUpdate)

    assert Enum.count(actions, &(&1.name == :append and &1.type == :create)) == 1
    refute Enum.any?(actions, &(&1.type in [:update, :destroy]))
    refute Enum.any?(actions, &(&1.name == :upsert))
  end

  defp publish_node(context, suffix) do
    actor = agent_actor(context)

    {:ok, draft} =
      Node
      |> Ash.Changeset.for_create(
        :create_publication,
        %{
          tree_id: context.tree.id,
          kind: :audit,
          title: "Evidence node #{suffix}",
          manifest_digest: String.duplicate("a", 64),
          idempotency_key: "#{suffix}-#{context.identity.token_id}",
          siwa_envelope: %{"body" => "{}"}
        },
        actor: actor
      )
      |> Ash.create()

    {:ok, publishing} =
      draft
      |> Ash.Changeset.for_update(:mark_publication_publishing, %{}, actor: actor)
      |> Ash.update()

    {:ok, published} =
      publishing
      |> Ash.Changeset.for_update(
        :mark_publication_published,
        %{published_at: DateTime.utc_now()},
        actor: actor
      )
      |> Ash.update()

    published
  end

  defp draft_node(context, suffix) do
    actor = agent_actor(context)

    {:ok, draft} =
      Node
      |> Ash.Changeset.for_create(
        :create_publication,
        %{
          tree_id: context.tree.id,
          kind: :audit,
          title: "Draft node #{suffix}",
          manifest_digest: String.duplicate("b", 64),
          idempotency_key: "#{suffix}-#{context.identity.token_id}",
          siwa_envelope: %{"body" => "{}"}
        },
        actor: actor
      )
      |> Ash.create()

    draft
  end

  defp agent_actor(context) do
    %AgentIdentity{
      agent_id: context.identity.agent_id,
      registry_address: context.identity.registry_address,
      token_id: context.identity.token_id,
      wallet: context.identity.wallet,
      regent_id: context.regent.id,
      agent_link_id: context.link.id,
      audience: "ash-platform-test"
    }
  end

  defp node_columns(node) do
    attributes = Ash.Resource.Info.attributes(Node)
    Map.take(Map.from_struct(node), Enum.map(attributes, & &1.name))
  end

  defp update_columns(update) do
    attributes = Ash.Resource.Info.attributes(EvidenceStateUpdate)
    Map.take(Map.from_struct(update), Enum.map(attributes, & &1.name))
  end
end
