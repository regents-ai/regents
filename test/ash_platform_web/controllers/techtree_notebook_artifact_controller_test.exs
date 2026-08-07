defmodule AshPlatformWeb.TechtreeNotebookArtifactControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation, Techtree}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.AgentAuth.AgentIdentity
  alias AshPlatform.Techtree.Node

  @registry "0x1111111111111111111111111111111111111111"
  @wallet "0x2222222222222222222222222222222222222222"
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
    artifact = artifact_request(node_payload_hash, "browser local")

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
      assert response.status == 422
      assert json_response(response, 422)["error"]["code"] == Atom.to_string(code)
      assert artifact_count(node.id) == 0
    end
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
    do: post_artifact(node_id, artifact, verification_result, [], "")

  defp post_artifact(node_id, artifact, verification_result, headers, query)
       when is_map(artifact) do
    post_artifact(node_id, Jason.encode!(artifact), verification_result, headers, query)
  end

  defp post_artifact(node_id, body, verification_result, headers, query) when is_binary(body) do
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
      "/api/techtree/v1/nodes/#{node_id}/notebook-artifact#{query}",
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

  defp artifact_count(node_id) do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        AshPlatform.Repo,
        "SELECT count(*) FROM techtree.notebook_artifacts WHERE node_id = $1",
        [Ecto.UUID.dump!(node_id)]
      )

    count
  end

  defp hash_hex("sha256:" <> hex), do: hex

  defp sha256(value),
    do: "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
end
