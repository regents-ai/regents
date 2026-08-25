defmodule AshPlatformWeb.TechtreeNotebookArtifactControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation, Techtree}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.AgentAuth.AgentIdentity
  alias AshPlatform.Formation.AgentLink
  alias AshPlatform.Techtree.{Node, NotebookArtifact}

  @registry "0x1111111111111111111111111111111111111111"
  @wallet "0x2222222222222222222222222222222222222222"
  @other_registry "0x3333333333333333333333333333333333333333"
  @other_wallet "0x4444444444444444444444444444444444444444"
  @marimo_version "0.23.14"
  @allowed_assets [
    "https://cdn.jsdelivr.net",
    "https://wasm.marimo.app",
    "https://files.pythonhosted.org"
  ]

  setup do
    Process.delete(:agent_verification_result)

    on_exit(fn -> Process.delete(:agent_verification_result) end)

    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!(
        "did:privy:techtree-notebook-http:#{unique}",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    human = %Human{human_account_id: account.id}

    regent =
      Formation.form_regent!("notebook-http-#{unique}", "Notebook HTTP #{unique}", actor: human)

    identity = %{
      agent_id: "agent-notebook-http-#{unique}",
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

  test "owner HTTP import returns the exact public artifact shape", context do
    node_payload_hash = sha256("node payload")
    node = publish_node(context, "happy", node_payload_hash)
    artifact = generated_artifact(node_payload_hash)

    response = post_artifact(node.id, artifact, {:ok, context.identity}) |> json_response(201)
    data = response["data"]

    assert Enum.sort(Map.keys(data)) ==
             Enum.sort([
               "id",
               "node_id",
               "node_payload_hash",
               "source_hash",
               "payload_hash",
               "marimo_version",
               "runtime",
               "compatibility",
               "run_url",
               "allowed_assets",
               "inserted_at"
             ])

    assert data["node_id"] == node.id
    assert data["node_payload_hash"] == artifact.node_payload_hash
    assert data["source_hash"] == artifact.source_hash
    assert data["payload_hash"] == artifact.payload_hash
    assert data["marimo_version"] == @marimo_version
    assert data["runtime"] == "pyodide"
    assert data["compatibility"] == "verified"
    assert data["run_url"] == artifact.run_url
    assert data["allowed_assets"] == @allowed_assets
    refute Map.has_key?(data, "manifest_json")
    assert {:ok, _inserted_at, 0} = DateTime.from_iso8601(data["inserted_at"])

    assert {:ok, [stored]} = Techtree.list_current_notebook_artifacts(node.id, node_payload_hash)
    assert stored.id == data["id"]
    assert stored.manifest_json == artifact.manifest_json
  end

  test "all existing Proof-negative cases return 422 and create no artifact", context do
    node_payload_hash = sha256("node payload")
    node = publish_node(context, "proof-negatives", node_payload_hash)
    valid = artifact_request(node_payload_hash, "browser local")
    existing = artifact_request(node_payload_hash, "existing identity")

    post_artifact(node.id, existing, {:ok, context.identity}) |> json_response(201)

    before_node = node_columns(node)
    {:ok, [existing_row]} = Techtree.list_current_notebook_artifacts(node.id, node_payload_hash)
    before_existing = notebook_columns(existing_row)

    invalid_requests = [
      {:invalid_notebook_artifact, Map.put(valid, :payload_hash, sha256("different bytes"))},
      {:stale_node_payload, %{valid | node_payload_hash: sha256("stale node payload")}},
      {:invalid_notebook_artifact, %{valid | marimo_version: "0.22.0"}},
      {:invalid_notebook_artifact,
       %{
         valid
         | run_url: "http://notebooks.example.com/#{hash_hex(valid.payload_hash)}/index.html"
       }},
      {:invalid_notebook_artifact,
       %{valid | run_url: "https://notebooks.example.com/not-the-payload/"}},
      {:invalid_notebook_artifact, %{valid | manifest_json: "{}"}}
    ]

    for {code, invalid} <- invalid_requests do
      response = post_artifact(node.id, invalid, {:ok, context.identity})

      assert_notebook_rejection(
        response,
        422,
        code,
        node,
        before_node,
        1,
        existing_row.id,
        before_existing
      )
    end
  end

  test "a run URL over 2,048 characters is a request-shape error", context do
    node_payload_hash = sha256("run-url-size")
    node = publish_node(context, "run-url-size", node_payload_hash)
    valid = artifact_request(node_payload_hash, "run-url-size source")
    existing = artifact_request(node_payload_hash, "run-url-size existing")

    post_artifact(node.id, existing, {:ok, context.identity}) |> json_response(201)

    before_node = node_columns(node)
    {:ok, [existing_row]} = Techtree.list_current_notebook_artifacts(node.id, node_payload_hash)
    before_existing = notebook_columns(existing_row)
    oversized = Map.put(valid, :run_url, String.duplicate("x", 2_049))

    response = post_artifact(node.id, oversized, {:ok, context.identity})

    assert_notebook_rejection(
      response,
      400,
      :invalid_request,
      node,
      before_node,
      1,
      existing_row.id,
      before_existing
    )
  end

  test "notebook storage failures after identity precheck return a temporary-unavailable error",
       context do
    node_payload_hash = sha256("notebook-storage")
    node = publish_node(context, "notebook-storage", node_payload_hash)
    before_node = node_columns(node)
    artifact = artifact_request(node_payload_hash, "notebook-storage source")
    test_pid = self()

    importer = fn _storage_call ->
      send(test_pid, :notebook_storage_called)

      {:error,
       Ash.Error.to_error_class(RuntimeError.exception("notebook artifact storage unavailable"))}
    end

    response = post_artifact(node.id, artifact, {:ok, context.identity}, importer)

    assert_received :notebook_storage_called
    assert response.status == 503
    assert json_response(response, 503)["error"]["code"] == "temporarily_unavailable"
    assert artifact_count(node.id) == 0
    # Reads the stored node row unfiltered by policy so the raw columns can be compared.
    assert node_columns(Ash.get!(Node, node.id, authorize?: false)) == before_node
  end

  test "concurrent duplicate imports return conflict", context do
    node_payload_hash = sha256("concurrent duplicate")
    node = publish_node(context, "concurrent-duplicate", node_payload_hash)
    artifact = artifact_request(node_payload_hash, "concurrent duplicate source")
    importer = concurrent_importer(self())

    tasks =
      for _index <- 1..2 do
        Task.async(fn ->
          post_artifact(node.id, artifact, {:ok, context.identity}, importer)
        end)
      end

    storage_pids =
      for _task <- tasks do
        assert_receive {:notebook_storage_ready, pid}, 5_000
        pid
      end

    Enum.each(storage_pids, &send(&1, :insert))
    responses = Enum.map(tasks, &Task.await(&1, 15_000))

    assert Enum.sort(Enum.map(responses, & &1.status)) == [201, 409]

    conflict = Enum.find(responses, &(&1.status == 409))
    assert json_response(conflict, 409)["error"]["code"] == "conflict"
    assert artifact_count(node.id) == 1
  end

  test "unpaired, revoked, re-paired, different-Regent, and cross-owner HTTP cases fail closed",
       context do
    node_payload_hash = sha256("http-authorization")
    node = publish_node(context, "http-authorization", node_payload_hash)
    artifact = artifact_request(node_payload_hash, "http authorization source")
    before_node = node_columns(node)

    unpaired = %{
      agent_id: "unpaired-#{Elixir.System.unique_integer([:positive])}",
      registry_address: @registry,
      token_id: "unpaired-#{Elixir.System.unique_integer([:positive])}",
      wallet: @wallet
    }

    assert_http_error_unchanged(
      post_artifact(node.id, artifact, {:ok, unpaired}),
      403,
      :forbidden,
      node,
      before_node,
      0
    )

    assert :ok = Formation.revoke_agent_link(context.link, actor: context.human)

    assert_http_error_unchanged(
      post_artifact(node.id, artifact, {:ok, context.identity}),
      403,
      :forbidden,
      node,
      before_node,
      0
    )

    repaired_link = pair_link(context.identity, context.regent.id, context.human.human_account_id)

    assert post_artifact(node.id, artifact, {:ok, context.identity}) |> json_response(201)
    assert artifact_count(node.id) == 1

    assert :ok = Formation.revoke_agent_link(repaired_link, actor: context.human)
    other_regent = new_owner_context("notebook-different-regent")
    pair_link(context.identity, other_regent.regent.id, other_regent.human.human_account_id)

    assert_http_error_unchanged(
      post_artifact(
        node.id,
        artifact_request(node_payload_hash, "different regent source"),
        {:ok, context.identity}
      ),
      403,
      :forbidden,
      node,
      before_node,
      1
    )

    owner = new_owner_context("notebook-cross-owner")
    other_node_payload_hash = sha256("cross-owner node")
    other_node = publish_node(owner, "cross-owner", other_node_payload_hash)
    other_before_node = node_columns(other_node)

    assert_http_error_unchanged(
      post_artifact(
        other_node.id,
        artifact_request(other_node_payload_hash, "cross-owner source"),
        {:ok, context.identity}
      ),
      403,
      :forbidden,
      other_node,
      other_before_node,
      0
    )
  end

  test "same identity retries conflict without mutation and a new source creates a row",
       context do
    node_payload_hash = sha256("node payload")
    node = publish_node(context, "identity", node_payload_hash)
    first = artifact_request(node_payload_hash, "browser local")

    created = post_artifact(node.id, first, {:ok, context.identity}) |> json_response(201)
    first_id = created["data"]["id"]

    duplicate = post_artifact(node.id, first, {:ok, context.identity})
    assert duplicate.status == 409
    assert json_response(duplicate, 409)["error"]["code"] == "conflict"

    changed_fields = Map.put(first, :run_url, "http://127.0.0.1:4003/changed/index.html")
    changed = post_artifact(node.id, changed_fields, {:ok, context.identity})
    assert changed.status == 409
    assert json_response(changed, 409)["error"]["code"] == "conflict"

    assert {:ok, [stored]} = Techtree.list_current_notebook_artifacts(node.id, node_payload_hash)
    assert stored.id == first_id
    assert stored.run_url == first.run_url
    assert stored.manifest_json == first.manifest_json

    second = artifact_request(node_payload_hash, "second source")
    created_second = post_artifact(node.id, second, {:ok, context.identity}) |> json_response(201)
    refute created_second["data"]["id"] == first_id
    assert artifact_count(node.id) == 2
  end

  test "agent and system notebook actions keep their separate authorization boundaries",
       context do
    node_payload_hash = sha256("domain policy node")
    node = publish_node(context, "domain-policy", node_payload_hash)
    artifact = artifact_request(node_payload_hash, "domain policy source")

    assert {:error, %Ash.Error.Forbidden{}} =
             Techtree.import_agent_notebook_artifact(
               node.id,
               artifact.node_payload_hash,
               artifact.source_hash,
               artifact.payload_hash,
               artifact.marimo_version,
               artifact.run_url,
               artifact.manifest_json,
               artifact.allowed_assets,
               actor: %System{}
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Techtree.import_agent_notebook_artifact(
               node.id,
               artifact.node_payload_hash,
               artifact.source_hash,
               artifact.payload_hash,
               artifact.marimo_version,
               artifact.run_url,
               artifact.manifest_json,
               artifact.allowed_assets,
               actor: %{role: :agent}
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Techtree.import_notebook_artifact(
               node.id,
               artifact.node_payload_hash,
               artifact.source_hash,
               artifact.payload_hash,
               artifact.marimo_version,
               artifact.run_url,
               artifact.manifest_json,
               artifact.allowed_assets,
               actor: agent_actor(context)
             )
  end

  test "manifest byte bound, body bound, and query strictness fail before import", context do
    node_payload_hash = sha256("size node")
    node = publish_node(context, "sizes", node_payload_hash)
    valid = artifact_request(node_payload_hash, "size source")

    oversized_manifest = Map.put(valid, :manifest_json, String.duplicate("x", 524_289))
    manifest_response = post_artifact(node.id, oversized_manifest, {:ok, context.identity})
    assert manifest_response.status == 400
    assert json_response(manifest_response, 400)["error"]["code"] == "invalid_request"
    assert artifact_count(node.id) == 0

    body = Jason.encode!(valid) <> String.duplicate(" ", 4_194_304)
    body_response = post_artifact(node.id, body, {:ok, context.identity})
    assert body_response.status == 413
    assert json_response(body_response, 413)["error"]["code"] == "payload_too_large"
    assert artifact_count(node.id) == 0

    query_response =
      post_artifact(node.id, valid, {:ok, context.identity}, [], "?unexpected=true")

    assert query_response.status == 400
    assert json_response(query_response, 400)["error"]["code"] == "invalid_request"
    assert artifact_count(node.id) == 0
  end

  defp publish_node(context, suffix, payload_hash) do
    actor = agent_actor(context)

    {:ok, draft} =
      Node
      |> Ash.Changeset.for_create(
        :create_publication,
        %{
          tree_id: context.tree.id,
          kind: :audit,
          title: "HTTP notebook node #{suffix}",
          payload_hash: payload_hash,
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

  defp artifact_request(node_payload_hash, source_label) do
    source_hash = sha256(source_label)
    manifest_json = valid_manifest_json(source_hash)
    payload_hash = sha256(manifest_json)

    %{
      node_payload_hash: node_payload_hash,
      source_hash: source_hash,
      payload_hash: payload_hash,
      marimo_version: @marimo_version,
      run_url: "http://127.0.0.1:4003/#{hash_hex(payload_hash)}/index.html",
      manifest_json: manifest_json,
      allowed_assets: @allowed_assets
    }
  end

  defp generated_artifact(node_payload_hash) do
    AshPlatform.TestMarimoArtifact.artifact()
    |> Map.put(:node_payload_hash, node_payload_hash)
  end

  defp valid_manifest_json(source_hash) do
    Jason.encode!(%{
      "schema_version" => 1,
      "runtime" => "pyodide",
      "marimo_version" => @marimo_version,
      "source_hash" => source_hash,
      "files" => [%{"path" => "index.html", "sha256" => sha256("index bytes")}]
    })
  end

  defp post_artifact(node_id, artifact, verification_result),
    do: post_artifact(node_id, artifact, verification_result, [], "", nil)

  defp post_artifact(node_id, artifact, verification_result, importer),
    do: post_artifact(node_id, artifact, verification_result, [], "", importer)

  defp post_artifact(node_id, artifact, verification_result, headers, query),
    do: post_artifact(node_id, artifact, verification_result, headers, query, nil)

  defp post_artifact(node_id, artifact, verification_result, headers, query, importer)
       when is_map(artifact) do
    post_artifact(
      node_id,
      Jason.encode!(artifact),
      verification_result,
      headers,
      query,
      importer
    )
  end

  defp post_artifact(node_id, body, verification_result, headers, query, importer)
       when is_binary(body) do
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
      if importer do
        put_private(conn, :techtree_notebook_artifact_importer, importer)
      else
        conn
      end

    conn =
      Enum.reduce(headers, conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    Phoenix.ConnTest.dispatch(
      conn,
      AshPlatformWeb.Endpoint,
      :post,
      "/api/techtree/v1/nodes/#{node_id}/notebook-artifact#{query}",
      body
    )
  end

  defp concurrent_importer(test_pid) do
    fn storage_call ->
      send(test_pid, {:notebook_storage_ready, self()})

      receive do
        :insert ->
          storage_call.()
      after
        5_000 ->
          {:error, Ash.Error.to_error_class(RuntimeError.exception("insert timeout"))}
      end
    end
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

  defp artifact_count(node_id) do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        "SELECT count(*) FROM techtree.notebook_artifacts WHERE node_id = $1",
        [Ecto.UUID.dump!(node_id)]
      )

    count
  end

  defp assert_notebook_rejection(
         response,
         status,
         code,
         node,
         before_node,
         before_count,
         existing_id,
         before_existing
       ) do
    assert response.status == status
    assert json_response(response, status)["error"]["code"] == Atom.to_string(code)
    assert artifact_count(node.id) == before_count
    # Reads the stored node row unfiltered by policy so the raw columns can be compared.
    assert node_columns(Ash.get!(Node, node.id, authorize?: false)) == before_node
    {:ok, [existing]} = Techtree.list_current_notebook_artifacts(node.id, node.payload_hash)
    assert existing.id == existing_id
    assert notebook_columns(existing) == before_existing
  end

  defp assert_http_error_unchanged(response, status, code, node, before_node, before_count) do
    assert response.status == status
    assert json_response(response, status)["error"]["code"] == Atom.to_string(code)
    assert artifact_count(node.id) == before_count
    # Reads the stored node row unfiltered by policy so the raw columns can be compared.
    assert node_columns(Ash.get!(Node, node.id, authorize?: false)) == before_node
  end

  defp new_owner_context(suffix) do
    unique = Elixir.System.unique_integer([:positive])
    wallet = @other_wallet

    account =
      Accounts.register_verified!(
        "did:privy:#{suffix}:#{unique}",
        wallet,
        [wallet],
        actor: %System{}
      )

    human = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("#{suffix}-#{unique}", "#{suffix} #{unique}", actor: human)

    identity = %{
      agent_id: "agent-#{suffix}-#{unique}",
      registry_address: @other_registry,
      token_id: Integer.to_string(unique),
      wallet: wallet
    }

    link = pair_link(identity, regent.id, human.human_account_id)
    tree = Techtree.get_tree_by_slug!("skill-training-lab")
    %{identity: identity, link: link, regent: regent, human: human, tree: tree}
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

  defp node_columns(node) do
    attributes = Ash.Resource.Info.attributes(Node)
    Map.take(Map.from_struct(node), Enum.map(attributes, & &1.name))
  end

  defp notebook_columns(artifact) do
    attributes = Ash.Resource.Info.attributes(NotebookArtifact)
    Map.take(Map.from_struct(artifact), Enum.map(attributes, & &1.name))
  end

  defp hash_hex("sha256:" <> hex), do: hex

  defp sha256(value),
    do: "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
end
