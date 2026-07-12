defmodule Mix.Tasks.AshPlatform.ResetBrowserComments do
  use Mix.Task

  @shortdoc "Removes only the local test records owned by the browser comment proof"

  @tree_slug "skill-training-lab"
  @markers [
    {"Browser comment fixture", "A local record for the end-to-end comment proof.", nil},
    {"Browser notebook fixture", "A local Marimo notebook running on this device.",
     "sha256:browser-notebook-node-payload"}
  ]

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    reset!()
  end

  def reset!(opts \\ []) do
    env = Keyword.get(opts, :env, current_env())
    repo_config = Keyword.get(opts, :repo_config, AshPlatform.Repo.config())
    validate_test_target!(env, repo_config)

    AshPlatform.Repo.transaction(fn ->
      node_ids = fixture_node_ids!()

      unless node_ids == [] do
        query!(
          """
          DELETE FROM discussions.comment_reactions
          WHERE comment_id IN (
            SELECT id FROM discussions.comments
            WHERE target_type = 'techtree_node' AND target_id = ANY($1::uuid[])
          )
          """,
          [node_ids]
        )

        query!(
          "DELETE FROM discussions.comments WHERE target_type = 'techtree_node' AND target_id = ANY($1::uuid[])",
          [node_ids]
        )

        query!("DELETE FROM techtree.notebook_artifacts WHERE node_id = ANY($1::uuid[])", [
          node_ids
        ])

        query!("DELETE FROM techtree.nodes WHERE id = ANY($1::uuid[])", [node_ids])
      end

      length(node_ids)
    end)
    |> case do
      {:ok, count} -> count
      {:error, error} -> raise error
    end
  end

  def validate_test_target!(env, repo_config) do
    AshPlatform.LocalDatabaseFixture.validate_target!(env, repo_config)
    database = to_string(repo_config[:database])

    if env == :test and String.ends_with?(database, "_test") do
      :ok
    else
      raise "browser fixture reset refused unsafe database target"
    end
  end

  defp fixture_node_ids! do
    rows =
      query!(
        """
        SELECT nodes.id, nodes.title, nodes.summary, nodes.payload_hash
        FROM techtree.nodes AS nodes
        JOIN techtree.trees AS trees ON trees.id = nodes.tree_id
        WHERE trees.slug = $1 AND nodes.title = ANY($2::text[])
        FOR UPDATE
        """,
        [@tree_slug, Enum.map(@markers, &elem(&1, 0))]
      ).rows

    Enum.flat_map(@markers, fn {title, summary, payload_hash} ->
      titled = Enum.filter(rows, fn [_id, row_title, _summary, _hash] -> row_title == title end)

      exact =
        Enum.filter(titled, fn [_id, _title, row_summary, row_hash] ->
          row_summary == summary and row_hash == payload_hash
        end)

      case {titled, exact} do
        {[], []} -> []
        {[_], [[id, _title, _summary, _hash]]} -> [id]
        {_, []} -> raise "browser fixture marker mismatch for #{title}"
        {_, _} -> raise "ambiguous browser fixture marker for #{title}"
      end
    end)
  end

  defp query!(sql, params), do: Ecto.Adapters.SQL.query!(AshPlatform.Repo, sql, params)

  defp current_env do
    if Code.ensure_loaded?(Mix), do: Mix.env(), else: :prod
  end
end
