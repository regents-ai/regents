defmodule Mix.Tasks.AshPlatform.SeedBrowserComments do
  use Mix.Task

  @shortdoc "Seeds the one persistent record needed by the comment browser proof"

  @tree_slug "skill-training-lab"
  @comment_marker %{
    title: "Browser comment fixture",
    summary: "A local record for the end-to-end comment proof.",
    payload_hash: nil
  }
  @notebook_marker %{
    title: "Browser notebook fixture",
    summary: "A local Marimo notebook running on this device.",
    payload_hash: "sha256:browser-notebook-node-payload"
  }

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    AshPlatform.LocalDatabaseFixture.ensure_human_accounts!()

    seed!()
  end

  def seed! do
    tree = AshPlatform.Techtree.get_tree_by_slug!(@tree_slug)
    nodes = AshPlatform.Techtree.list_tree_nodes!(tree.id)

    case fixture_node!(nodes, @comment_marker) do
      nil ->
        AshPlatform.Techtree.import_public_node!(
          tree.id,
          @comment_marker.title,
          @comment_marker.summary,
          @comment_marker.payload_hash,
          actor: %AshPlatform.Actors.System{}
        )

      _node ->
        :ok
    end

    notebook_node =
      case fixture_node!(nodes, @notebook_marker) do
        nil ->
          AshPlatform.Techtree.import_public_node!(
            tree.id,
            @notebook_marker.title,
            @notebook_marker.summary,
            @notebook_marker.payload_hash,
            actor: %AshPlatform.Actors.System{}
          )

        node ->
          node
      end

    artifact = AshPlatform.TestMarimoArtifact.artifact()

    case AshPlatform.Techtree.list_current_notebook_artifacts!(
           notebook_node.id,
           notebook_node.payload_hash
         ) do
      [] ->
        AshPlatform.Techtree.import_notebook_artifact!(
          notebook_node.id,
          notebook_node.payload_hash,
          artifact.source_hash,
          artifact.payload_hash,
          artifact.marimo_version,
          artifact.run_url,
          artifact.manifest_json,
          artifact.allowed_assets,
          actor: %AshPlatform.Actors.System{}
        )

      [_artifact] ->
        :ok
    end
  end

  defp fixture_node!(nodes, marker) do
    titled = Enum.filter(nodes, &(&1.title == marker.title))

    exact =
      Enum.filter(titled, fn node ->
        node.summary == marker.summary and node.payload_hash == marker.payload_hash
      end)

    case {titled, exact} do
      {[], []} -> nil
      {[_], [node]} -> node
      {_, []} -> raise "browser fixture marker mismatch for #{marker.title}"
      {_, _} -> raise "ambiguous browser fixture marker for #{marker.title}"
    end
  end
end
