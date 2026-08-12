defmodule AshPlatformWeb.TechtreeEvidenceControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation, Techtree}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.AgentAuth.AgentIdentity
  alias AshPlatform.Formation.AgentLink
  alias AshPlatform.Techtree.{EvidenceStateUpdate, Node}

  @registry "0x1111111111111111111111111111111111111111"
  @wallet "0x2222222222222222222222222222222222222222"

  setup do
    Process.delete(:agent_verification_result)
    Process.delete(:capture_agent_verification_calls)

    on_exit(fn ->
      Process.delete(:agent_verification_result)
      Process.delete(:capture_agent_verification_calls)
    end)

    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!(
        "did:privy:techtree-evidence-http:#{unique}",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    human = %Human{human_account_id: account.id}

    regent =
      Formation.form_regent!("evidence-http-#{unique}", "Evidence HTTP #{unique}", actor: human)

    identity = %{
      agent_id: "agent-evidence-http-#{unique}",
      registry_address: @registry,
      token_id: Integer.to_string(unique),
      wallet: @wallet
    }

    link = pair_link(identity, regent.id, account.id)
    :ok = Techtree.ensure_seed_trees(actor: %System{})
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    %{identity: identity, link: link, regent: regent, human: human, tree: tree}
  end

  test "owner append returns the declared response and preserves the raw envelope", context do
    node = publish_node(context, "happy")
    before_columns = node_columns(node)
    body = %{"status" => "reproduced", "reason" => "Reproduced by the publishing agent."}
    raw_body = Jason.encode!(body)

    response = post_evidence(node.id, raw_body, {:ok, context.identity}) |> json_response(201)
    data = response["data"]

    assert Enum.sort(Map.keys(data)) ==
             Enum.sort([
               "id",
               "node_id",
               "status",
               "reason",
               "evidence_reference_ids",
               "updated_at"
             ])

    assert data["node_id"] == node.id
    assert data["status"] == "reproduced"
    assert data["reason"] == body["reason"]
    assert data["evidence_reference_ids"] == []
    assert {:ok, inserted_at, 0} = DateTime.from_iso8601(data["updated_at"])

    assert {:ok, [stored]} = EvidenceStateUpdate.all_for_node(node.id)
    assert stored.id == data["id"]
    assert stored.siwa_envelope["method"] == "POST"
    assert stored.siwa_envelope["path"] == "/api/techtree/v1/nodes/#{node.id}/evidence-state"
    assert stored.siwa_envelope["body"] == raw_body
    assert stored.submitter_agent_id == context.identity.agent_id
    assert stored.submitter_registry_address == context.identity.registry_address
    assert stored.submitter_token_id == context.identity.token_id
    assert stored.submitter_wallet == context.identity.wallet
    assert stored.submitter_chain_id == 8453
    assert stored.submitter_regent_id == context.regent.id
    assert DateTime.compare(stored.inserted_at, inserted_at) == :eq
    assert node_columns(node) == before_columns
  end

  test "node detail returns the latest appended evidence state", context do
    node = publish_node(context, "read")

    assert get(build_conn(), "/api/techtree/v1/nodes/#{node.id}")
           |> json_response(200)
           |> get_in(["data", "evidence_state"]) == %{
             "status" => "issued",
             "evidence_reference_ids" => [],
             "updated_at" => DateTime.to_iso8601(node.published_at)
           }

    body = %{"status" => "disputed", "reason" => "Needs independent reproduction."}
    post_evidence(node.id, Jason.encode!(body), {:ok, context.identity}) |> json_response(201)

    detail = get(build_conn(), "/api/techtree/v1/nodes/#{node.id}") |> json_response(200)
    state = detail["data"]["evidence_state"]

    assert state["status"] == "disputed"
    assert state["reason"] == body["reason"]
    assert state["evidence_reference_ids"] == []
    assert is_binary(state["updated_at"])
  end

  test "evidence requests are strict and reject unknown fields, aliases, and queries", context do
    node = publish_node(context, "strict")
    initial_count = evidence_count(node.id)
    before_columns = node_columns(node)

    for invalid <- [
          %{"status" => "issued"},
          %{"status" => "awaiting_revalidation"},
          %{"status" => "reproduced", "reason" => ""},
          %{"status" => "reproduced", "evidence_class" => "invalid"},
          %{"status" => "reproduced", "evidence_projection" => %{}},
          %{"status" => "reproduced", "projection_status" => "confirmed"},
          %{"status" => "reproduced", "workflow_state" => "published"},
          %{"status" => "reproduced", "payload_hash" => "sha256:payload"},
          %{"status" => "reproduced", "integrity_status" => "verified"},
          %{"status" => "reproduced", "experimental_strength" => "high"},
          %{"reason" => "missing status"}
        ] do
      response = post_evidence(node.id, Jason.encode!(invalid), {:ok, context.identity})

      assert_rejection_unchanged(
        response,
        400,
        :invalid_request,
        node,
        before_columns,
        initial_count
      )
    end

    response =
      post_evidence(
        node.id,
        Jason.encode!(%{"status" => "reproduced"}),
        {:ok, context.identity},
        [],
        "?unexpected=true"
      )

    assert_rejection_unchanged(
      response,
      400,
      :invalid_request,
      node,
      before_columns,
      initial_count
    )
  end

  test "invalid, private, missing, and self references return 422 without an append", context do
    node = publish_node(context, "references")
    private = draft_node(context, "private-reference")
    invalid_ids = [Ash.UUID.generate(), private.id, node.id]
    before_columns = node_columns(node)

    for reference_id <- invalid_ids do
      body = %{"status" => "reproduced", "evidence_reference_ids" => [reference_id]}
      response = post_evidence(node.id, Jason.encode!(body), {:ok, context.identity})

      assert_rejection_unchanged(
        response,
        422,
        :invalid_evidence_reference,
        node,
        before_columns,
        0
      )
    end
  end

  test "target visibility and ownership are checked before the action", context do
    node = publish_node(context, "target-checks")

    system_node =
      Techtree.import_public_node!(context.tree.id, "System public node", nil, nil,
        actor: %System{}
      )

    draft = draft_node(context, "target-draft")
    body = Jason.encode!(%{"status" => "reproduced"})
    before_node = node_columns(node)
    before_system_node = node_columns(system_node)
    before_draft = node_columns(draft)

    malformed = post_evidence("not-a-uuid", body, {:ok, context.identity})
    assert_rejection_unchanged(malformed, 400, :invalid_request, node, before_node, 0)

    missing = post_evidence(Ash.UUID.generate(), body, {:ok, context.identity})
    assert_rejection_unchanged(missing, 404, :not_found, node, before_node, 0)

    private = post_evidence(draft.id, body, {:ok, context.identity})
    assert_rejection_unchanged(private, 404, :not_found, draft, before_draft, 0)

    non_owner = post_evidence(system_node.id, body, {:ok, context.identity})
    assert_rejection_unchanged(non_owner, 403, :forbidden, system_node, before_system_node, 0)

    assert evidence_count(node.id) == 0
    assert node_columns(node) == before_node
  end

  test "verification failures, Privy cookie, and Bearer auth fail closed", context do
    node = publish_node(context, "auth")
    body = Jason.encode!(%{"status" => "reproduced"})
    before_columns = node_columns(node)
    Process.put(:capture_agent_verification_calls, true)

    rejected = post_evidence(node.id, body, {:error, :verification_failed})
    assert_rejection_unchanged(rejected, 401, :unauthorized, node, before_columns, 0)

    unavailable = post_evidence(node.id, body, {:error, :verification_unavailable})

    assert_rejection_unchanged(
      unavailable,
      503,
      :temporarily_unavailable,
      node,
      before_columns,
      0
    )

    assert_received {:agent_verification, _envelope}
    assert_received {:agent_verification, _envelope}
    Process.delete(:capture_agent_verification_calls)

    for header <- [
          {"cookie", "_ash_platform_key=privy-session"},
          {"authorization", "Bearer privy-access-token"}
        ] do
      response = post_evidence(node.id, body, {:ok, context.identity}, [header])
      assert_rejection_unchanged(response, 401, :unauthorized, node, before_columns, 0)
    end

    refute_received {:agent_verification, _envelope}
    assert evidence_count(node.id) == 0
  end

  test "a re-paired identity with a changed publisher tuple remains forbidden", context do
    node = publish_node(context, "re-paired")
    before_columns = node_columns(node)
    changed_wallet = "0x3333333333333333333333333333333333333333"

    assert :ok = Formation.revoke_agent_link(context.link, actor: context.human)
    identity = %{context.identity | wallet: changed_wallet}

    assert identity.agent_id == context.identity.agent_id
    assert identity.registry_address == context.identity.registry_address
    assert identity.token_id == context.identity.token_id
    refute identity.wallet == context.identity.wallet
    pair_link(identity, context.regent.id, context.human.human_account_id)

    body = Jason.encode!(%{"status" => "reproduced"})
    response = post_evidence(node.id, body, {:ok, identity})

    assert_rejection_unchanged(response, 403, :forbidden, node, before_columns, 0)
  end

  test "a re-paired identity under a different Regent remains forbidden", context do
    node = publish_node(context, "different-regent-repair")
    before_columns = node_columns(node)
    other = alternate_owner_context("different-regent-repair")

    assert :ok = Formation.revoke_agent_link(context.link, actor: context.human)
    pair_link(context.identity, other.regent.id, other.human.human_account_id)

    response =
      post_evidence(node.id, Jason.encode!(%{"status" => "reproduced"}), {:ok, context.identity})

    assert_rejection_unchanged(response, 403, :forbidden, node, before_columns, 0)
  end

  test "each persisted publisher field is required for the HTTP owner check", context do
    node = publish_node(context, "tuple-fields")
    body = Jason.encode!(%{"status" => "reproduced"})
    before_columns = node_columns(node)

    for {column, value} <- [
          {:publisher_agent_id, "different-agent"},
          {:publisher_registry_address, "0x3333333333333333333333333333333333333333"},
          {:publisher_token_id, "different-token"},
          {:publisher_wallet, "0x3333333333333333333333333333333333333333"},
          {:publisher_chain_id, 1},
          {:publisher_regent_id, Ash.UUID.generate()}
        ] do
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        "UPDATE techtree.nodes SET #{column} = $1 WHERE id = $2",
        [sql_value(column, value), Ecto.UUID.dump!(node.id)]
      )

      mutated_columns = node_columns(node)
      response = post_evidence(node.id, body, {:ok, context.identity})
      assert_rejection_unchanged(response, 403, :forbidden, node, mutated_columns, 0)

      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        "UPDATE techtree.nodes SET #{column} = $1 WHERE id = $2",
        [sql_value(column, Map.fetch!(node, column)), Ecto.UUID.dump!(node.id)]
      )

      assert node_columns(node) == before_columns
    end
  end

  test "a revoked link is rejected even when its old node tuple remains", context do
    node = publish_node(context, "revoked")
    before_columns = node_columns(node)

    assert :ok = Formation.revoke_agent_link(context.link, actor: context.human)

    response =
      post_evidence(node.id, Jason.encode!(%{"status" => "reproduced"}), {:ok, context.identity})

    assert_rejection_unchanged(response, 403, :forbidden, node, before_columns, 0)
  end

  test "the evidence body limit distinguishes exact-limit input from one byte over", context do
    node = publish_node(context, "body-limit")
    before_columns = node_columns(node)
    exact = body_at_size(65_536)

    exact_response = post_evidence(node.id, exact, {:ok, context.identity})

    assert_rejection_unchanged(
      exact_response,
      400,
      :invalid_request,
      node,
      before_columns,
      0
    )

    Process.put(:capture_agent_verification_calls, true)
    over = body_at_size(65_537)
    over_response = post_evidence(node.id, over, {:ok, context.identity})

    assert_rejection_unchanged(
      over_response,
      413,
      :payload_too_large,
      node,
      before_columns,
      0
    )

    refute_received {:agent_verification, _envelope}
  end

  test "concurrent owner appends both commit and GET selects the forced tie winner", context do
    node = publish_node(context, "concurrent")
    parent = self()

    tasks =
      for {status, reason} <- [
            {"reproduced", "concurrent reproduction"},
            {"disputed", "concurrent dispute"}
          ] do
        Task.async(fn ->
          Process.put(:agent_verification_result, {:ok, context.identity})
          send(parent, {:ready, self()})

          receive do
            :go ->
              post_evidence(
                node.id,
                Jason.encode!(%{"status" => status, "reason" => reason}),
                {:ok, context.identity}
              )
          end
        end)
      end

    Enum.each(tasks, fn _task -> assert_receive {:ready, _pid}, 1_000 end)
    Enum.each(tasks, fn task -> send(task.pid, :go) end)

    responses = Enum.map(tasks, &Task.await(&1, 5_000))
    assert Enum.map(responses, & &1.status) == [201, 201]
    assert evidence_count(node.id) == 2

    tied_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {:ok, updates} = EvidenceStateUpdate.all_for_node(node.id)

    for update <- updates do
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        "UPDATE techtree.evidence_state_updates SET inserted_at = $1 WHERE id = $2",
        [tied_at, Ecto.UUID.dump!(update.id)]
      )
    end

    winner = Enum.max_by(updates, & &1.id)
    detail = get(build_conn(), "/api/techtree/v1/nodes/#{node.id}") |> json_response(200)
    state = detail["data"]["evidence_state"]

    assert state["status"] == Atom.to_string(winner.status)
    assert state["reason"] == winner.reason
    assert state["updated_at"] == DateTime.to_iso8601(tied_at)
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
          title: "HTTP evidence node #{suffix}",
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
          title: "HTTP draft node #{suffix}",
          manifest_digest: String.duplicate("b", 64),
          idempotency_key: "#{suffix}-#{context.identity.token_id}",
          siwa_envelope: %{"body" => "{}"}
        },
        actor: actor
      )
      |> Ash.create()

    draft
  end

  defp post_evidence(node_id, body, verification_result),
    do: post_evidence(node_id, body, verification_result, [], "")

  defp post_evidence(node_id, body, verification_result, headers),
    do: post_evidence(node_id, body, verification_result, headers, "")

  defp post_evidence(node_id, body, verification_result, headers, query) do
    Process.put(:agent_verification_result, verification_result)

    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-siwa-receipt", "test-receipt")
      |> put_req_header("x-key-id", "test-key")
      |> put_req_header("x-timestamp", "1785888000")
      |> put_req_header("x-agent-wallet-address", @wallet)
      |> put_req_header("x-agent-chain-id", "8453")
      |> put_req_header("x-agent-registry-address", @registry)
      |> put_req_header("x-agent-token-id", "test-token")
      |> put_req_header("signature-input", "test-input")
      |> put_req_header("signature", "test-signature")
      |> put_req_header("content-digest", "sha-256=:redacted:")

    conn =
      Enum.reduce(headers, conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    Phoenix.ConnTest.dispatch(
      conn,
      AshPlatformWeb.Endpoint,
      :post,
      "/api/techtree/v1/nodes/#{node_id}/evidence-state#{query}",
      body
    )
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

  defp evidence_count(node_id) do
    {:ok, rows} = EvidenceStateUpdate.all_for_node(node_id)
    length(rows)
  end

  defp assert_rejection_unchanged(response, status, code, node, before_columns, before_count) do
    assert response.status == status
    assert json_response(response, status)["error"]["code"] == Atom.to_string(code)
    assert evidence_count(node.id) == before_count
    assert node_columns(node) == before_columns
  end

  defp alternate_owner_context(suffix) do
    unique = Elixir.System.unique_integer([:positive])
    wallet = "0x4444444444444444444444444444444444444444"

    account =
      Accounts.register_verified!(
        "did:privy:#{suffix}:#{unique}",
        wallet,
        [wallet],
        actor: %System{}
      )

    human = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("#{suffix}-#{unique}", "#{suffix} #{unique}", actor: human)

    %{human: human, regent: regent}
  end

  defp pair_link(identity, regent_id, human_account_id) do
    {:ok, link} =
      AgentLink
      |> Ash.Changeset.for_create(
        :pair,
        %{
          human_account_id: human_account_id,
          regent_id: regent_id,
          agent_id: identity.agent_id,
          registry_address: identity.registry_address,
          token_id: identity.token_id,
          wallet: identity.wallet,
          paired_at: DateTime.utc_now()
        },
        actor: %System{}
      )
      |> Ash.create()

    link
  end

  defp sql_value(:publisher_regent_id, value), do: Ecto.UUID.dump!(value)
  defp sql_value(_column, value), do: value

  defp body_at_size(size) do
    base = Jason.encode!(%{"status" => "reproduced", "padding" => ""})
    padding = String.duplicate("x", size - byte_size(base))
    body = Jason.encode!(%{"status" => "reproduced", "padding" => padding})
    assert byte_size(body) == size
    body
  end

  defp node_columns(node) do
    result =
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        "SELECT * FROM techtree.nodes WHERE id = $1",
        [Ecto.UUID.dump!(node.id)]
      )

    assert [values] = result.rows
    Map.new(Enum.zip(result.columns, values))
  end
end
