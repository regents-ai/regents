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

    issued = Formation.issue_agent_pairing_code!(regent.id, actor: human)
    link = Formation.claim_agent_link!(regent.id, issued.code, identity, actor: %System{})
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
    assert node_columns(Ash.get!(Node, node.id, authorize?: false)) == before_columns
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
      assert response.status == 400
      assert json_response(response, 400)["error"]["code"] == "invalid_request"
      assert evidence_count(node.id) == initial_count
    end

    response =
      post_evidence(
        node.id,
        Jason.encode!(%{"status" => "reproduced"}),
        {:ok, context.identity},
        [],
        "?unexpected=true"
      )

    assert response.status == 400
    assert json_response(response, 400)["error"]["code"] == "invalid_request"
    assert evidence_count(node.id) == initial_count
  end

  test "invalid, private, missing, and self references return 422 without an append", context do
    node = publish_node(context, "references")
    private = draft_node(context, "private-reference")
    invalid_ids = [Ash.UUID.generate(), private.id, node.id]

    for reference_id <- invalid_ids do
      body = %{"status" => "reproduced", "evidence_reference_ids" => [reference_id]}
      response = post_evidence(node.id, Jason.encode!(body), {:ok, context.identity})

      assert response.status == 422
      assert json_response(response, 422)["error"]["code"] == "invalid_evidence_reference"
      assert evidence_count(node.id) == 0
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

    malformed = post_evidence("not-a-uuid", body, {:ok, context.identity})
    assert malformed.status == 400
    assert json_response(malformed, 400)["error"]["code"] == "invalid_request"

    missing = post_evidence(Ash.UUID.generate(), body, {:ok, context.identity})
    assert missing.status == 404
    assert json_response(missing, 404)["error"]["code"] == "not_found"

    private = post_evidence(draft.id, body, {:ok, context.identity})
    assert private.status == 404
    assert json_response(private, 404)["error"]["code"] == "not_found"

    non_owner = post_evidence(system_node.id, body, {:ok, context.identity})
    assert non_owner.status == 403
    assert json_response(non_owner, 403)["error"]["code"] == "forbidden"

    assert evidence_count(node.id) == 0
  end

  test "verification failures, Privy cookie, and Bearer auth fail closed", context do
    node = publish_node(context, "auth")
    body = Jason.encode!(%{"status" => "reproduced"})
    Process.put(:capture_agent_verification_calls, true)

    rejected = post_evidence(node.id, body, {:error, :verification_failed})
    assert rejected.status == 401
    assert json_response(rejected, 401)["error"]["code"] == "unauthorized"

    unavailable = post_evidence(node.id, body, {:error, :verification_unavailable})
    assert unavailable.status == 503
    assert json_response(unavailable, 503)["error"]["code"] == "temporarily_unavailable"
    assert_received {:agent_verification, _envelope}
    assert_received {:agent_verification, _envelope}
    Process.delete(:capture_agent_verification_calls)

    for header <- [
          {"cookie", "_ash_platform_key=privy-session"},
          {"authorization", "Bearer privy-access-token"}
        ] do
      response = post_evidence(node.id, body, {:ok, context.identity}, [header])
      assert response.status == 401
      assert json_response(response, 401)["error"]["code"] == "unauthorized"
    end

    refute_received {:agent_verification, _envelope}
    assert evidence_count(node.id) == 0
  end

  test "a re-paired identity with a changed publisher tuple remains forbidden", context do
    node = publish_node(context, "re-paired")
    changed_wallet = "0x3333333333333333333333333333333333333333"

    identity = %{
      agent_id: "agent-repaired-#{Elixir.System.unique_integer([:positive])}",
      registry_address: context.identity.registry_address,
      token_id: "repaired-#{Elixir.System.unique_integer([:positive])}",
      wallet: changed_wallet
    }

    assert {:ok, _link} =
             AgentLink
             |> Ash.Changeset.for_create(
               :pair,
               %{
                 human_account_id: context.human.human_account_id,
                 regent_id: context.regent.id,
                 agent_id: identity.agent_id,
                 registry_address: identity.registry_address,
                 token_id: identity.token_id,
                 wallet: identity.wallet,
                 paired_at: DateTime.utc_now()
               },
               actor: %System{}
             )
             |> Ash.create()

    body = Jason.encode!(%{"status" => "reproduced"})
    response = post_evidence(node.id, body, {:ok, identity})

    assert response.status == 403
    assert json_response(response, 403)["error"]["code"] == "forbidden"
    assert evidence_count(node.id) == 0
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

  defp node_columns(node) do
    attributes = Ash.Resource.Info.attributes(Node)
    Map.take(Map.from_struct(node), Enum.map(attributes, & &1.name))
  end
end
