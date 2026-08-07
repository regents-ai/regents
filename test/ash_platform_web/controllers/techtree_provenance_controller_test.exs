defmodule AshPlatformWeb.TechtreeProvenanceControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation, Techtree}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Techtree.{Node, Payload}

  defmodule HttpClient do
    def get(_url, _options),
      do:
        Application.get_env(
          :ash_platform,
          :techtree_test_payload_response,
          {:error, :missing_stub}
        )
  end

  setup do
    previous = Application.get_env(:ash_platform, :techtree_payload)

    Application.put_env(:ash_platform, :techtree_payload,
      gateway_url: "https://gateway.test/ipfs",
      timeout: 25,
      max_bytes: 1_024,
      http_client: HttpClient
    )

    on_exit(fn ->
      Application.delete_env(:ash_platform, :techtree_test_payload_response)
      restore(:techtree_payload, previous)
    end)

    {:ok, tree: tree!("provenance")}
  end

  test "node detail and payload access expose matching provenance", %{conn: conn, tree: tree} do
    profile = public_profile!()
    parent = Techtree.import_public_node!(tree.id, "Parent", nil, nil, actor: %System{})
    payload = uplift_payload()
    hash = Payload.sha256(payload)

    node =
      public_node!(tree, %{
        title: "Published uplift",
        summary: "A public uplift result.",
        kind: :uplift_report,
        manifest_cid: "bafybeiprovenance",
        manifest_hash: hash,
        manifest_uri: "ipfs://bafybeiprovenance",
        lineage: %{parent.id => "supports"},
        contributor_id: "agent-provenance",
        publisher_regent_id: profile.id,
        projection_status: :confirmed
      })

    put_payload_response({:ok, %{status: 200, body: payload}})

    detail = get(conn, "/api/techtree/v1/nodes/#{node.id}") |> json_response(200)
    data = detail["data"]

    assert data["contributor"] == %{
             "agent_id" => "agent-provenance",
             "profile_url" => "/regents/#{profile.slug}"
           }

    assert data["published_at"] == DateTime.to_iso8601(node.published_at)
    assert data["lineage"] == [%{"node_id" => parent.id, "kind" => "supports"}]
    assert data["manifest_cid"] == "bafybeiprovenance"
    assert data["manifest_hash"] == hash
    assert data["manifest_uri"] == "ipfs://bafybeiprovenance"
    assert data["payload_url"] == "/api/techtree/v1/nodes/#{node.id}/payload"

    assert data["payload_verification"] == %{
             "status" => "hash_matched",
             "expected_hash" => hash,
             "actual_hash" => hash
           }

    assert data["projection_status"] == "confirmed"

    page = get(conn, "/api/techtree/v1/trees/#{tree.slug}/nodes") |> json_response(200)
    list_data = Enum.find(page["data"], &(&1["id"] == node.id))
    assert list_data["contributor"]["agent_id"] == "agent-provenance"
    assert list_data["lineage"] == [%{"node_id" => parent.id, "kind" => "supports"}]
    assert list_data["payload_verification"]["status"] == "not_checked"
    assert list_data["projection_status"] == "confirmed"

    payload_response = get(conn, "/api/techtree/v1/nodes/#{node.id}/payload")
    assert payload_response.status == 200
    assert payload_response.resp_body == payload

    assert Plug.Conn.get_resp_header(payload_response, "content-type") == [
             "application/json; charset=utf-8"
           ]

    {:ok, view, _html} = live(conn, "/techtree/nodes/#{node.id}")
    html = render_async(view)

    for question <- [
          "Did it help?",
          "How capable is the final agent?",
          "What got better or worse?",
          "What did it cost?",
          "How strong is the evidence?"
        ] do
      assert html =~ question
    end

    assert html =~ "Helped"
    assert html =~ "advanced"
    assert html =~ "+2 held-out tasks"
    assert html =~ "Single run"
    assert html =~ "Reproduction package included"
    assert html =~ "Possible contamination"
    assert html =~ "Held-out evaluation"
    assert html =~ "Calibration (public references)"
    assert html =~ "Inspect evidence"
    assert html =~ "Projection"
    assert html =~ "Confirmed"
    refute html =~ "legacy"
  end

  test "roots and projection states are rendered without inventing lineage", %{
    conn: conn,
    tree: tree
  } do
    node = public_node!(tree, %{title: "Pending root", projection_status: :pending})

    detail = get(conn, "/api/techtree/v1/nodes/#{node.id}") |> json_response(200)
    assert detail["data"]["lineage"] == []
    assert detail["data"]["projection_status"] == "pending"

    {:ok, view, _html} = live(conn, "/techtree/nodes/#{node.id}")
    html = render_async(view)
    assert html =~ "Pending root"
    assert html =~ "Pending"
    assert html =~ "Root node"
  end

  test "missing, mismatched, and corrupt artifacts are unavailable rather than not found", %{
    conn: conn,
    tree: tree
  } do
    cases = [
      {"missing", "valid", {:ok, %{status: 404, body: ""}}},
      {"mismatch", ~s({"schema_version":"uplift-report-v1"}),
       {:ok, %{status: 200, body: ~s({"schema_version":"uplift-report-v1"})}}},
      {"corrupt", "not-json", {:ok, %{status: 200, body: "not-json"}}}
    ]

    for {suffix, body, response} <- cases do
      expected_hash =
        case suffix do
          "mismatch" -> String.duplicate("0", 64)
          _suffix -> Payload.sha256(body)
        end

      node =
        public_node!(tree, %{
          title: "Unavailable #{suffix}",
          manifest_cid: "bafybei#{suffix}",
          manifest_hash: expected_hash
        })

      put_payload_response(response)

      detail = get(conn, "/api/techtree/v1/nodes/#{node.id}")
      assert detail.status == 424
      assert json_response(detail, 424)["error"]["code"] == "artifact_unavailable"

      payload = get(conn, "/api/techtree/v1/nodes/#{node.id}/payload")
      assert payload.status == 424
      assert json_response(payload, 424)["error"]["code"] == "artifact_unavailable"
    end
  end

  test "a node without a manifest remains readable while payload fetch reports unavailability", %{
    conn: conn,
    tree: tree
  } do
    node = Techtree.import_public_node!(tree.id, "No manifest", nil, nil, actor: %System{})

    detail = get(conn, "/api/techtree/v1/nodes/#{node.id}") |> json_response(200)
    assert detail["data"]["payload_verification"]["status"] == "not_available"

    payload = get(conn, "/api/techtree/v1/nodes/#{node.id}/payload")
    assert payload.status == 424
    assert json_response(payload, 424)["error"]["code"] == "artifact_unavailable"
  end

  defp public_profile! do
    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!(
        "did:privy:zs66-profile-#{unique}",
        "0x1111111111111111111111111111111111111111",
        ["0x1111111111111111111111111111111111111111"],
        actor: %System{}
      )

    Formation.form_regent!(
      "zs66-profile-#{unique}",
      "zs6.6 Profile #{unique}",
      actor: %Human{human_account_id: account.id}
    )
  end

  defp public_node!(tree, attributes) do
    Ash.Seed.seed!(
      Node,
      Map.merge(
        %{
          tree_id: tree.id,
          title: "Provenance node",
          summary: nil,
          payload_hash: nil,
          kind: :audit,
          lineage: %{},
          projection_status: :not_started,
          workflow_state: :published,
          published_at: ~U[2030-01-01 00:00:00.000000Z]
        },
        attributes
      )
    )
  end

  defp uplift_payload do
    Jason.encode!(%{
      "schema_version" => "uplift-report-v1",
      "report_id" => "report-provenance",
      "outcome" => "positive",
      "final_capability_level" => "advanced",
      "measured_change" => "+2 held-out tasks",
      "evidence_class" => "single_run",
      "reproduction_status" => "not_run",
      "reproduction_package_status" => "available",
      "cost_latency" => "$1.84 / 42 seconds",
      "scored_evaluation" => %{"held_out" => %{"delta" => 2}},
      "calibration" => %{"scores" => %{"public_reference" => 1}}
    })
  end

  defp tree!(suffix) do
    unique = Elixir.System.unique_integer([:positive])

    Techtree.upsert_seed_tree!(
      "zs66-#{suffix}-#{unique}",
      "zs6.6 #{suffix} #{unique}",
      "Public test tree.",
      2_000_000 + unique,
      actor: %System{}
    )
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)

  defp put_payload_response(response),
    do: Application.put_env(:ash_platform, :techtree_test_payload_response, response)
end
