defmodule CredoAsh.Check.Warning.DirectRepoCall do
  @moduledoc "Reports undocumented repository calls that bypass Ash actions."

  use Credo.Check,
    id: "CRA1006",
    base_priority: :high,
    category: :warning,
    tags: [:credo_ash],
    explanations: [
      check: """
      Reaching for `Repo` on a resource-backed table skips the whole Ash layer:
      no policies, no changes, no validations, no notifications, no audit trail.
      Use an action or a bulk action instead.

          # bad
          Repo.insert_all(MyApp.Blog.Post, rows)

          # good
          Ash.bulk_create!(rows, MyApp.Blog.Post, :create)

      Raw SQL (`Repo.query/2`, used for advisory locks and the like) touches no
      resource and is not flagged.

      Sometimes the bypass is the point — an idempotent insert leaning on a
      unique index, or a teardown deleting rows for a resource with no destroy
      action. Say so in a comment above the call and the finding clears; what
      matters is that a reader can tell the deliberate case from the accident.
      """
    ]

  @calls [
    :all,
    :one,
    :get,
    :get!,
    :get_by,
    :get_by!,
    :insert,
    :insert!,
    :update,
    :update!,
    :delete,
    :delete!,
    :insert_all,
    :update_all,
    :delete_all,
    :preload,
    :aggregate
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, {issue_meta, source_file}))
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, parts}, fun]}, meta, _args} = ast,
         issues,
         {issue_meta, source_file}
       )
       when fun in @calls do
    if List.last(parts) == :Repo and
         not CredoAsh.Justification.justified?(source_file, meta[:line]) do
      {ast, issues ++ [issue_for(issue_meta, meta[:line], fun)]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp issue_for(issue_meta, line_no, fun) do
    format_issue(issue_meta,
      message:
        "`Repo.#{fun}` bypasses Ash — policies, changes and notifications never run. " <>
          "Use an action or a bulk action, or say in a comment why this one goes around it.",
      trigger: "Repo.#{fun}",
      line_no: line_no
    )
  end
end
