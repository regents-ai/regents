defmodule AshPlatformWeb.TechtreePublicationControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation, Techtree}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.AgentAuth.{AgentIdentity, ClaimRateLimiter}
  alias AshPlatform.Techtree.{Node, PublicationInput}

  @registry "0x1111111111111111111111111111111111111111"
  @wallet "0x2222222222222222222222222222222222222222"
  @kinds ~w(environment_family benchmark_slice uplift_report reproduction audit)
  @receipt_keys ~w(action_id capability_id action_kind resource_type resource_id status idempotency_key created_at updated_at public_url next_recommended_action next_poll_at approval_required error_code replayed)

  setup do
    Process.delete(:agent_verification_result)
    Process.delete(:capture_agent_verification_calls)
    ClaimRateLimiter.reset()

    on_exit(fn ->
      Process.delete(:agent_verification_result)
      Process.delete(:capture_agent_verification_calls)
      ClaimRateLimiter.reset()
    end)

    :ok
  end

  setup context do
    if context[:publisher_fixture] == false, do: :ok, else: publisher_fixture()
  end

  defp publisher_fixture do
    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!(
        "did:privy:techtree-publication:#{unique}",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    human = %Human{human_account_id: account.id}

    regent =
      Formation.form_regent!("publication-#{unique}", "Publication #{unique}", actor: human)

    identity = %{
      agent_id: "agent-publication-#{unique}",
      registry_address: @registry,
      token_id: Integer.to_string(unique),
      wallet: @wallet
    }

    issued = Formation.issue_agent_pairing_code!(regent.id, actor: human)
    link = Formation.claim_agent_link!(regent.id, issued.code, identity, actor: %System{})
    :ok = Techtree.ensure_seed_trees(actor: %System{})
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    %{account: account, human: human, regent: regent, identity: identity, link: link, tree: tree}
  end

  test "a publisher within its configured rate remains admitted", context do
    with_publication_rate_limit(2, fn ->
      for index <- 1..2 do
        response =
          signed_post(
            request_body(context, "audit", "within-limit-#{index}"),
            {:ok, context.identity}
          )

        assert response.status == 201
      end

      assert publisher_publication_count(context) == 2
    end)
  end

  test "the publication budget rejects the next distinct publication", context do
    with_publication_rate_limit(2, fn ->
      for index <- 1..2 do
        response =
          signed_post(
            request_body(context, "audit", "over-limit-#{index}"),
            {:ok, context.identity}
          )

        assert response.status == 201
      end

      rejected =
        signed_post(request_body(context, "audit", "over-limit-3"), {:ok, context.identity})
        |> json_response(429)

      assert_failed_receipt(rejected, "rate_limited")
      assert rejected["error"]["message"] == "Too many publications. Please wait and try again."
      assert publisher_publication_count(context) == 2
    end)
  end

  test "publication budgets are isolated by publisher identity", context do
    other = pair_identity(context, "isolated")
    other_context = %{context | identity: other.identity, link: other.link, regent: other.regent}

    with_publication_rate_limit(1, fn ->
      response =
        signed_post(request_body(context, "audit", "identity-a-1"), {:ok, context.identity})

      assert response.status == 201

      rejected =
        signed_post(request_body(context, "audit", "identity-a-2"), {:ok, context.identity})
        |> json_response(429)

      assert_failed_receipt(rejected, "rate_limited")

      response =
        signed_post(request_body(other_context, "audit", "identity-b-1"), {:ok, other.identity})

      assert response.status == 201
      assert publisher_publication_count(context) == 1
      assert publisher_publication_count(other_context) == 1
    end)
  end

  test "accepted replays remain available at a full budget", context do
    with_publication_rate_limit(1, fn ->
      body = request_body(context, "audit", "accepted-replay-full")
      first = (signed_post(body, {:ok, context.identity}) |> json_response(201))["data"]

      replay =
        (raw_post(Jason.encode!(body), [{"signature", "fresh-replay-signature"}], {
           :ok,
           context.identity
         })
         |> json_response(200))["data"]

      assert Map.drop(replay, ["replayed"]) == Map.drop(first, ["replayed"])
      assert replay["replayed"] == true
    end)
  end

  test "accepted replays do not consume budget for a later distinct publication", context do
    with_publication_rate_limit(2, fn ->
      body = request_body(context, "audit", "accepted-replay-budget")
      first = (signed_post(body, {:ok, context.identity}) |> json_response(201))["data"]

      replay =
        (raw_post(Jason.encode!(body), [{"signature", "fresh-budget-replay-signature"}], {
           :ok,
           context.identity
         })
         |> json_response(200))["data"]

      assert Map.drop(replay, ["replayed"]) == Map.drop(first, ["replayed"])
      assert replay["replayed"] == true

      distinct =
        signed_post(
          request_body(context, "audit", "accepted-replay-distinct"),
          {:ok, context.identity}
        )
        |> json_response(201)

      assert distinct["data"]["replayed"] == false
      assert publisher_publication_count(context) == 2
    end)
  end

  test "invalid publication attempts still consume budget", context do
    with_publication_rate_limit(1, fn ->
      invalid = Map.put(request_body(context, "audit", "invalid-budget"), "kind", "unknown")

      assert_failed_receipt(
        signed_post(invalid, {:ok, context.identity}) |> json_response(400),
        "invalid_input"
      )

      assert_failed_receipt(
        signed_post(request_body(context, "audit", "after-invalid"), {:ok, context.identity})
        |> json_response(429),
        "rate_limited"
      )

      assert publisher_publication_count(context) == 0
    end)
  end

  test "the rate limiter table is owned by its supervised process", _context do
    limiter_pid = Process.whereis(ClaimRateLimiter)

    assert is_pid(limiter_pid)
    assert :ets.info(ClaimRateLimiter, :owner) == limiter_pid

    assert Enum.any?(Supervisor.which_children(AshPlatform.Supervisor), fn
             {ClaimRateLimiter, ^limiter_pid, :worker, _modules} -> true
             _child -> false
           end)
  end

  test "each node kind publishes and is visible through public API and Map/List", context do
    published =
      for {kind, index} <- Enum.with_index(@kinds) do
        body =
          request_body(context, kind, "kind-#{index}")

        response = signed_post(body, {:ok, context.identity})
        receipt = json_response(response, 201)["data"]

        assert Enum.sort(Map.keys(receipt)) == Enum.sort(@receipt_keys)
        assert receipt["capability_id"] == "techtree.node.publish"
        assert receipt["status"] == "published"
        assert receipt["replayed"] == false

        # Reads the row the request wrote, unfiltered by policy, to assert what was stored.
        node = Ash.get!(Node, receipt["resource_id"], authorize?: false)
        assert node.kind == String.to_existing_atom(kind)
        assert node.manifest_digest == String.duplicate(Integer.to_string(index + 1), 64)
        assert node.workflow_state == :published
        assert node.contributor_id == context.identity.agent_id
        assert node.publisher_agent_id == context.identity.agent_id
        assert node.publisher_registry_address == context.identity.registry_address
        assert node.publisher_token_id == context.identity.token_id
        assert node.publisher_regent_id == context.regent.id
        refute Map.has_key?(node, :human_account_id)
        node
      end

    first = hd(published)

    detail = get(build_conn(), "/api/techtree/v1/nodes/#{first.id}") |> json_response(200)
    assert detail["data"]["kind"] == "environment_family"
    assert detail["data"]["contributor_id"] == context.identity.agent_id
    assert detail["data"]["base_mainnet_projection"]["projection_status"] == "not_started"

    page =
      get(build_conn(), "/api/techtree/v1/trees/#{context.tree.slug}/nodes")
      |> json_response(200)

    assert Enum.all?(published, fn node ->
             Enum.any?(page["data"], &(&1["id"] == node.id))
           end)

    {:ok, view, _html} = live(build_conn(), "/techtree/#{context.tree.slug}")
    assert has_element?(view, ~s([data-techtree-map] a[href="/techtree/nodes/#{first.id}"]))

    assert has_element?(
             view,
             ~s([data-techtree-list-panel] a[href="/techtree/nodes/#{first.id}"])
           )
  end

  test "unknown top-level publication keys are rejected without creating a node", context do
    body =
      request_body(context, "audit", "unknown-top-level")
      |> Map.put("future_evidence_state", %{"status" => "issued"})

    response = signed_post(body, {:ok, context.identity}) |> json_response(400)

    assert_invalid_input_envelope(response, body["idempotency_key"])
    assert publisher_publication_count(context) == 0
    assert publication_count(context, body["idempotency_key"]) == 0
  end

  test "unknown lineage reference keys are rejected without creating a node", context do
    body =
      request_body(context, "uplift_report", "unknown-lineage-key")
      |> Map.put("lineage", [
        %{
          "node_id" => Ash.UUID.generate(),
          "kind" => "supports",
          "future_relation" => "not-supported"
        }
      ])

    response = signed_post(body, {:ok, context.identity}) |> json_response(400)

    assert_invalid_input_envelope(response, body["idempotency_key"])
    assert publisher_publication_count(context) == 0
    assert publication_count(context, body["idempotency_key"]) == 0
  end

  test "publication accepts manifest retrievability fields and typed lineage", context do
    parent_id = Ash.UUID.generate()
    digest = request_body(context, "uplift_report", "manifest-fields")["manifest_digest"]

    body =
      request_body(context, "uplift_report", "manifest-fields")
      |> Map.merge(%{
        "manifest_cid" => "bafybeipublication",
        "manifest_hash" => digest,
        "manifest_uri" => "ipfs://bafybeipublication",
        "lineage" => [%{"node_id" => parent_id, "kind" => "supports"}]
      })

    response = signed_post(body, {:ok, context.identity}) |> json_response(201)
    # Reads the row the request wrote, unfiltered by policy, to assert what was stored.
    node = Ash.get!(Node, response["data"]["resource_id"], authorize?: false)

    assert node.manifest_cid == body["manifest_cid"]
    assert node.manifest_hash == digest
    assert node.manifest_uri == body["manifest_uri"]
    assert node.lineage == %{parent_id => "supports"}
  end

  test "replay compares normalized fields and preserves the first exact envelope", context do
    body =
      context
      |> request_body("audit", "replay")
      |> Map.put("title", "  Published audit  ")
      |> Map.put("idempotency_key", "  replay-#{context.identity.token_id}  ")

    encoded = Jason.encode!(body)

    first = raw_post(encoded, [{"signature", "first-signature"}], {:ok, context.identity})
    first_receipt = json_response(first, 201)["data"]

    # Reads the row the request wrote, unfiltered by policy, to assert what was stored.
    node = Ash.get!(Node, first_receipt["resource_id"], authorize?: false)
    Techtree.update_node_layout!(node, 10.0, 20.0, "featured", actor: %System{})

    replay = raw_post(encoded, [{"signature", "second-signature"}], {:ok, context.identity})
    replay_receipt = json_response(replay, 200)["data"]

    assert Map.drop(replay_receipt, ["replayed"]) == Map.drop(first_receipt, ["replayed"])
    assert replay_receipt["replayed"] == true

    # Reads the row the request wrote, unfiltered by policy, to assert what was stored.
    node = Ash.get!(Node, first_receipt["resource_id"], authorize?: false)
    assert node.title == "Published audit"
    assert node.idempotency_key == String.trim(body["idempotency_key"])
    assert node.siwa_envelope["body"] == encoded
    assert node.siwa_envelope["headers"]["signature"] == "first-signature"
    assert node.siwa_envelope["method"] == "POST"
    assert node.siwa_envelope["path"] == "/api/techtree/v1/nodes"
    assert publication_count(context, String.trim(body["idempotency_key"])) == 1
  end

  test "every persisted request string is normalized before persistence and replay comparison",
       context do
    assert PublicationInput.string_fields() ==
             ~w(
               regent_id
               tree_id
               kind
               title
               summary
               payload_hash
               idempotency_key
               manifest_digest
               manifest_cid
               manifest_hash
               manifest_uri
             )

    with_publication_rate_limit(length(PublicationInput.string_fields()) + 1, fn ->
      for field <- PublicationInput.string_fields() do
        body =
          context
          |> request_body("audit", "normalize-#{field}")
          |> Map.put_new("manifest_cid", "bafybeinormalize")
          |> Map.put_new("manifest_hash", String.duplicate("5", 64))
          |> Map.put_new("manifest_uri", "ipfs://bafybeinormalize")
          |> Map.update!(field, &(" \t" <> &1 <> <<0x85::utf8>>))

        encoded = Jason.encode!(body)
        first = raw_post(encoded, [{"signature", "first-#{field}"}], {:ok, context.identity})
        first_receipt = json_response(first, 201)["data"]

        replay = raw_post(encoded, [{"signature", "replay-#{field}"}], {:ok, context.identity})
        replay_receipt = json_response(replay, 200)["data"]

        assert Map.drop(replay_receipt, ["replayed"]) == Map.drop(first_receipt, ["replayed"])
        assert replay_receipt["replayed"] == true

        # Reads the row the request wrote, unfiltered by policy, to assert what was stored.
        node = Ash.get!(Node, first_receipt["resource_id"], authorize?: false)
        assert node.siwa_envelope["body"] == encoded
      end
    end)
  end

  test "blank idempotency keys are invalid and create no node", context do
    for key <- ["", " ", "\t\n", <<0x85::utf8>>] do
      body =
        context
        |> request_body("audit", "blank-key")
        |> Map.put("idempotency_key", key)

      response = signed_post(body, {:ok, context.identity}) |> json_response(400)
      assert_failed_receipt(response, "invalid_input")
    end

    assert publisher_publication_count(context) == 0
  end

  test "runtime idempotency admission agrees with the contract Unicode blank class", context do
    for {key, expected_status} <- [
          {" ", 400},
          {<<0x85::utf8>>, 400},
          {<<0xFEFF::utf8>>, 201}
        ] do
      body =
        context
        |> request_body("audit", "unicode-blank")
        |> Map.put("idempotency_key", key)

      response = signed_post(body, {:ok, context.identity})
      assert response.status == expected_status
    end

    assert publisher_publication_count(context) == 1
  end

  test "concurrent blank idempotency keys are invalid and create no node", context do
    parent = self()

    tasks =
      ["", " ", "\t\n", " ", "\t\n", ""]
      |> Enum.with_index()
      |> Enum.map(fn {key, index} ->
        body =
          context
          |> request_body("audit", "concurrent-blank-#{index}")
          |> Map.put("idempotency_key", key)

        Task.async(fn ->
          Process.put(:agent_verification_result, {:ok, context.identity})
          send(parent, {:ready, self()})

          receive do
            :publish -> signed_post(body, {:ok, context.identity})
          end
        end)
      end)

    pids =
      for _index <- tasks do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(pids, &send(&1, :publish))
    responses = Enum.map(tasks, &Task.await(&1, 15_000))

    assert Enum.map(responses, & &1.status) == List.duplicate(400, length(tasks))

    Enum.each(responses, fn response ->
      response.resp_body
      |> Jason.decode!()
      |> assert_failed_receipt("invalid_input")
    end)

    assert publisher_publication_count(context) == 0
  end

  test "concurrent duplicate keys create exactly one node", context do
    body = request_body(context, "benchmark_slice", "concurrent")
    encoded = Jason.encode!(body)
    parent = self()

    tasks =
      for index <- 1..8 do
        Task.async(fn ->
          Process.put(:agent_verification_result, {:ok, context.identity})
          send(parent, {:ready, self()})

          receive do
            :publish -> raw_post(encoded, [{"signature", "race-#{index}"}])
          end
        end)
      end

    pids =
      for _index <- 1..8 do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(pids, &send(&1, :publish))
    responses = Enum.map(tasks, &Task.await(&1, 15_000))

    assert Enum.sort(Enum.map(responses, & &1.status)) == List.duplicate(200, 7) ++ [201]

    receipts = Enum.map(responses, &Jason.decode!(&1.resp_body)["data"])
    assert receipts |> Enum.map(& &1["resource_id"]) |> Enum.uniq() |> length() == 1
    assert publication_count(context, body["idempotency_key"]) == 1
  end

  test "a concurrent accepted replay wins over a full publication budget", context do
    with_publication_rate_limit(1, fn ->
      body = request_body(context, "benchmark_slice", "concurrent-rate-limit")
      encoded = Jason.encode!(body)
      parent = self()

      tasks =
        for index <- 1..2 do
          Task.async(fn ->
            Process.put(:agent_verification_result, {:ok, context.identity})
            send(parent, {:ready, self()})

            receive do
              :publish -> raw_post(encoded, [{"signature", "concurrent-rate-#{index}"}])
            end
          end)
        end

      pids =
        for _index <- tasks do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(pids, &send(&1, :publish))
      responses = Enum.map(tasks, &Task.await(&1, 15_000))
      receipts = Enum.map(responses, &Jason.decode!(&1.resp_body)["data"])

      assert Enum.sort(Enum.map(responses, & &1.status)) == [200, 201]
      assert Enum.count(receipts, &(&1["replayed"] == false)) == 1
      assert Enum.count(receipts, &(&1["replayed"] == true)) == 1

      [created, replayed] =
        receipts
        |> Enum.sort_by(& &1["replayed"])

      assert Map.drop(replayed, ["replayed"]) == Map.drop(created, ["replayed"])
      assert publication_count(context, body["idempotency_key"]) == 1

      distinct =
        signed_post(
          request_body(context, "benchmark_slice", "concurrent-rate-distinct"),
          {:ok, context.identity}
        )
        |> json_response(429)

      assert_failed_receipt(distinct, "rate_limited")
    end)
  end

  test "unsigned, expired, and unverified requests fail closed", context do
    body = request_body(context, "reproduction", "unverified")

    unsigned =
      raw_post(Jason.encode!(body), [], {:error, :verification_failed})
      |> json_response(401)

    assert_failed_receipt(unsigned, "unauthorized")

    for reason <- [:expired_request, :unverified_signature] do
      response = signed_post(body, {:error, reason}) |> json_response(401)
      assert_failed_receipt(response, "unauthorized")
    end

    assert publication_count(context, body["idempotency_key"]) == 0
  end

  test "verified unpaired and cross-Regent agents are forbidden", context do
    body = request_body(context, "environment_family", "unpaired")

    unpaired = %{
      agent_id: "unpaired-agent",
      registry_address: "0x3333333333333333333333333333333333333333",
      token_id: "999",
      wallet: "0x4444444444444444444444444444444444444444"
    }

    assert_failed_receipt(signed_post(body, {:ok, unpaired}) |> json_response(403), "forbidden")

    other =
      Accounts.register_verified!(
        "did:privy:techtree-cross-regent:#{Elixir.System.unique_integer([:positive])}",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    other_regent =
      Formation.form_regent!(
        "cross-regent-#{Elixir.System.unique_integer([:positive])}",
        "Cross Regent",
        actor: %Human{human_account_id: other.id}
      )

    cross_body = Map.put(body, "regent_id", other_regent.id)

    assert_failed_receipt(
      signed_post(cross_body, {:ok, context.identity}) |> json_response(403),
      "forbidden"
    )
  end

  @tag publisher_fixture: false
  test "Privy cookie and bearer sessions never reach SIWA verification" do
    body = Jason.encode!(%{})
    Process.put(:capture_agent_verification_calls, true)

    for header <- [
          {"cookie", "_ash_platform_key=privy-session"},
          {"authorization", "Bearer privy-access-token"}
        ] do
      response = raw_post(body, [header]) |> json_response(401)
      assert_failed_receipt(response, "unauthorized")
      refute_received {:agent_verification, _envelope}
    end
  end

  test "invalid kind, digest, oversized input, and failed admission create no node", context do
    base = request_body(context, "audit", "invalid")

    for invalid <- [
          Map.put(base, "kind", "unknown"),
          Map.put(base, "manifest_digest", String.duplicate("A", 64)),
          Map.put(base, "manifest_cid", "bafybeiincomplete"),
          Map.merge(base, %{
            "manifest_cid" => "bafybeimismatch",
            "manifest_hash" => String.duplicate("f", 64)
          }),
          Map.put(base, "manifest_uri", "https://user:pass@example.test/manifest"),
          Map.put(base, "tree_id", Ash.UUID.generate())
        ] do
      response = signed_post(invalid, {:ok, context.identity}) |> json_response(400)
      assert_failed_receipt(response, "invalid_input")
    end

    Process.put(:capture_agent_verification_calls, true)

    oversized =
      base
      |> Map.put("idempotency_key", "oversized")
      |> Map.put("summary", String.duplicate("x", 66_000))
      |> Jason.encode!()

    response = raw_post(oversized, [], {:ok, context.identity}) |> json_response(400)
    assert_failed_receipt(response, "invalid_input")
    refute_received {:agent_verification, _envelope}

    assert publication_count(context, base["idempotency_key"]) == 0
    assert publication_count(context, "oversized") == 0
  end

  test "verifier outage fails closed as temporarily unavailable", context do
    body = request_body(context, "uplift_report", "verifier-down")

    response =
      signed_post(body, {:error, :verification_unavailable})
      |> json_response(503)

    assert_failed_receipt(response, "temporarily_unavailable")
    assert publication_count(context, body["idempotency_key"]) == 0
  end

  test "reuse with different publication content returns conflict and preserves the original",
       context do
    body = request_body(context, "audit", "conflict")
    first = signed_post(body, {:ok, context.identity}) |> json_response(201)

    changed = Map.put(body, "manifest_digest", String.duplicate("f", 64))
    conflict = signed_post(changed, {:ok, context.identity}) |> json_response(409)

    assert_failed_receipt(conflict, "conflict")
    assert publication_count(context, body["idempotency_key"]) == 1

    # Reads the row the request wrote, unfiltered by policy, to assert what was stored.
    node = Ash.get!(Node, first["data"]["resource_id"], authorize?: false)
    assert node.manifest_digest == body["manifest_digest"]
  end

  test "publication create without workflow_state lands as a non-public draft", context do
    attributes = %{
      tree_id: context.tree.id,
      kind: :audit,
      title: "Fail-safe state",
      manifest_digest: String.duplicate("a", 64),
      idempotency_key: "fail-safe-state-#{context.identity.token_id}",
      siwa_envelope: %{"body" => "{}"}
    }

    refute Map.has_key?(attributes, :workflow_state)
    assert Ash.Resource.Info.attribute(Node, :workflow_state).default == nil

    assert {:ok, draft} =
             Node
             |> Ash.Changeset.for_create(
               :create_publication,
               attributes,
               actor: agent_actor(context)
             )
             |> Ash.create()

    assert draft.workflow_state == :draft
    assert {:ok, nil} = Techtree.get_public_node(draft.id)
  end

  test "publication actions require the exact paired-agent actor", context do
    attributes = %{
      tree_id: context.tree.id,
      kind: :audit,
      title: "Policy test",
      manifest_digest: String.duplicate("a", 64),
      idempotency_key: "policy-test",
      siwa_envelope: %{"body" => "{}"}
    }

    for actor <- [nil, context.human, %{role: :agent}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Node
               |> Ash.Changeset.for_create(:create_publication, attributes, actor: actor)
               |> Ash.create()
    end

    agent_actor = agent_actor(context)

    assert {:ok, draft} =
             Node
             |> Ash.Changeset.for_create(:create_publication, attributes, actor: agent_actor)
             |> Ash.create()

    assert draft.workflow_state == :draft
    assert draft.publisher_agent_id == context.identity.agent_id

    assert {:error, %Ash.Error.Invalid{}} =
             Node
             |> Ash.Changeset.for_create(
               :create_publication,
               %{attributes | idempotency_key: " "},
               actor: agent_actor
             )
             |> Ash.create()

    forged = %{agent_actor | agent_link_id: Ash.UUID.generate()}

    assert {:error, %Ash.Error.Forbidden{}} =
             Node
             |> Ash.Changeset.for_create(
               :create_publication,
               %{attributes | idempotency_key: "forged-policy-test"},
               actor: forged
             )
             |> Ash.create()
  end

  test "the write route is admitted once and separately from browser-session writes" do
    routes = AshPlatformWeb.Router.__routes__()

    assert Enum.count(routes, fn route ->
             route.verb == :post and route.path == "/api/techtree/v1/nodes"
           end) == 1
  end

  defp request_body(context, kind, suffix) do
    digest_character = Integer.to_string(Enum.find_index(@kinds, &(&1 == kind)) + 1)

    %{
      "regent_id" => context.regent.id,
      "tree_id" => context.tree.id,
      "kind" => kind,
      "title" => "Published #{kind}",
      "summary" => "Public projection for #{kind}.",
      "payload_hash" => "sha256:#{suffix}",
      "idempotency_key" => "#{suffix}-#{context.identity.token_id}",
      "manifest_digest" => String.duplicate(digest_character, 64)
    }
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

  defp pair_identity(context, suffix) do
    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!(
        "did:privy:techtree-publication-#{suffix}:#{unique}",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    human = %Human{human_account_id: account.id}

    regent =
      Formation.form_regent!(
        "publication-#{suffix}-#{unique}",
        "Publication #{suffix} #{unique}",
        actor: human
      )

    identity = %{
      agent_id: "agent-publication-#{suffix}-#{unique}",
      registry_address: @registry,
      token_id: "#{context.identity.token_id}-#{suffix}-#{unique}",
      wallet: @wallet
    }

    issued = Formation.issue_agent_pairing_code!(regent.id, actor: human)
    link = Formation.claim_agent_link!(regent.id, issued.code, identity, actor: %System{})

    %{identity: identity, link: link, regent: regent}
  end

  defp signed_post(body, verification_result) do
    raw_post(Jason.encode!(body), [{"signature", "test-signature"}], verification_result)
  end

  defp raw_post(body, extra_headers, verification_result \\ nil) do
    if verification_result, do: Process.put(:agent_verification_result, verification_result)

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
      |> put_req_header("content-digest", "sha-256=:redacted:")

    conn =
      Enum.reduce(extra_headers, conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    Phoenix.ConnTest.dispatch(
      conn,
      AshPlatformWeb.Endpoint,
      :post,
      "/api/techtree/v1/nodes",
      body
    )
  end

  defp assert_failed_receipt(response, code) do
    assert response["error"]["code"] == code
    assert response["receipt"]["status"] == "failed"
    assert response["receipt"]["error_code"] == code
    assert response["receipt"]["resource_id"] == nil
    assert Enum.sort(Map.keys(response["receipt"])) == Enum.sort(@receipt_keys)
  end

  defp assert_invalid_input_envelope(response, idempotency_key) do
    assert_failed_receipt(response, "invalid_input")

    assert response["error"] == %{
             "code" => "invalid_input",
             "message" => "The publication request is invalid."
           }

    receipt = response["receipt"]
    assert {:ok, _action_id} = Ecto.UUID.cast(receipt["action_id"])
    assert receipt["capability_id"] == "techtree.node.publish"
    assert receipt["action_kind"] == "publish"
    assert receipt["resource_type"] == "techtree_node"
    assert receipt["idempotency_key"] == idempotency_key
    assert receipt["created_at"] == receipt["updated_at"]
    assert {:ok, _created_at, 0} = DateTime.from_iso8601(receipt["created_at"])
    assert receipt["public_url"] == nil
    assert receipt["next_recommended_action"] == "correct_publication_request"
    assert receipt["next_poll_at"] == nil
    assert receipt["approval_required"] == false
    assert receipt["replayed"] == false
  end

  defp with_publication_rate_limit(limit, fun) do
    previous = Application.fetch_env!(:ash_platform, :techtree_publication_rate_limit)

    Application.put_env(
      :ash_platform,
      :techtree_publication_rate_limit,
      limit: limit,
      window_seconds: 60
    )

    try do
      fun.()
    after
      Application.put_env(:ash_platform, :techtree_publication_rate_limit, previous)
      ClaimRateLimiter.reset()
    end
  end

  defp publication_count(context, idempotency_key) do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        """
        SELECT count(*)
        FROM techtree.nodes
        WHERE publisher_registry_address = $1
          AND publisher_token_id = $2
          AND idempotency_key = $3
        """,
        [context.identity.registry_address, context.identity.token_id, idempotency_key]
      )

    count
  end

  defp publisher_publication_count(context) do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        """
        SELECT count(*)
        FROM techtree.nodes
        WHERE publisher_registry_address = $1
          AND publisher_token_id = $2
        """,
        [context.identity.registry_address, context.identity.token_id]
      )

    count
  end
end
