defmodule AshPlatform.Techtree.NotebookArtifactTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Techtree

  @marimo_version "0.23.14"
  @allowed_assets [
    "https://cdn.jsdelivr.net",
    "https://wasm.marimo.app",
    "https://files.pythonhosted.org"
  ]

  test "a system import attaches one verified WASM export to the current node payload" do
    node = import_node("sha256:node-payload")
    source_hash = sha256("print('browser local')")
    manifest_json = valid_manifest_json(source_hash)
    payload_hash = sha256(manifest_json)
    run_url = run_url(payload_hash)

    assert {:ok, artifact} =
             Techtree.import_notebook_artifact(
               node.id,
               node.payload_hash,
               source_hash,
               payload_hash,
               @marimo_version,
               run_url,
               manifest_json,
               @allowed_assets,
               actor: %System{}
             )

    assert artifact.node_id == node.id
    assert artifact.runtime == :pyodide
    assert artifact.compatibility == :verified
    assert artifact.run_url == run_url

    assert {:ok, [public]} =
             Techtree.list_current_notebook_artifacts(node.id, node.payload_hash)

    assert public.id == artifact.id
    assert public.payload_hash == payload_hash
  end

  test "tampered, stale, or unsupported notebook artifacts fail closed" do
    node = import_node("sha256:current-node-payload")
    source_hash = sha256("print('browser local')")
    manifest_json = valid_manifest_json(source_hash)
    payload_hash = sha256(manifest_json)
    valid_run_url = run_url(payload_hash)

    for attrs <- [
          [
            node.payload_hash,
            source_hash,
            sha256("different bytes"),
            @marimo_version,
            valid_run_url,
            manifest_json
          ],
          [
            "sha256:stale-node-payload",
            source_hash,
            payload_hash,
            @marimo_version,
            valid_run_url,
            manifest_json
          ],
          [
            node.payload_hash,
            source_hash,
            payload_hash,
            "0.22.0",
            valid_run_url,
            manifest_json
          ],
          [
            node.payload_hash,
            source_hash,
            sha256("{}"),
            @marimo_version,
            run_url(sha256("{}")),
            "{}"
          ],
          [
            node.payload_hash,
            source_hash,
            payload_hash,
            @marimo_version,
            "http://notebooks.example.com/#{hash_hex(payload_hash)}/",
            manifest_json
          ],
          [
            node.payload_hash,
            source_hash,
            payload_hash,
            @marimo_version,
            "https://notebooks.example.com/not-the-payload/",
            manifest_json
          ]
        ] do
      [
        node_payload_hash,
        candidate_source_hash,
        candidate_payload_hash,
        version,
        candidate_run_url,
        candidate_manifest
      ] = attrs

      assert {:error, _error} =
               Techtree.import_notebook_artifact(
                 node.id,
                 node_payload_hash,
                 candidate_source_hash,
                 candidate_payload_hash,
                 version,
                 candidate_run_url,
                 candidate_manifest,
                 @allowed_assets,
                 actor: %System{}
               )
    end

    assert {:ok, []} =
             Techtree.list_current_notebook_artifacts(node.id, node.payload_hash)
  end

  test "notebook artifact writes reject missing, human, and lookalike system actors" do
    node = import_node("sha256:node-payload")
    source_hash = sha256("source")
    manifest_json = valid_manifest_json(source_hash)
    payload_hash = sha256(manifest_json)

    for actor <- [nil, %{role: :system}, %{role: :human, human_account_id: 1}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Techtree.import_notebook_artifact(
                 node.id,
                 node.payload_hash,
                 source_hash,
                 payload_hash,
                 @marimo_version,
                 run_url(payload_hash),
                 manifest_json,
                 @allowed_assets,
                 actor: actor
               )
    end
  end

  defp import_node(payload_hash) do
    tree = Techtree.get_tree_by_slug!("bixbench-capsule-lab")

    Techtree.import_public_node!(
      tree.id,
      "Local notebook evidence",
      "A browser-run notebook.",
      payload_hash,
      actor: %System{}
    )
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

  defp run_url(payload_hash),
    do: "http://127.0.0.1:4003/#{hash_hex(payload_hash)}/index.html"

  defp hash_hex("sha256:" <> hex), do: hex

  defp sha256(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end
end
