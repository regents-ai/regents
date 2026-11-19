defmodule CredoAsh.Check.Design.WildcardAccept do
  @moduledoc "Reports wildcard attribute acceptance in Ash actions."

  use Credo.Check,
    id: "CRA2001",
    base_priority: :normal,
    category: :design,
    tags: [:credo_ash, :security],
    explanations: [
      check: """
      `accept :*` lets a caller write every public attribute of the resource,
      including ones the action was never meant to touch. Name the attributes
      the action owns.

          # bad
          create :sign_up do
            accept :*
          end

          # good
          create :sign_up do
            accept [:email, :display_name]
          end

      Internal and admin-only actions sometimes want the wildcard; leave a
      comment saying so and configure this check off for those files.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:accept, meta, [arg]} = ast, issues, issue_meta) do
    if wildcard?(arg) do
      {ast, issues ++ [issue_for(issue_meta, meta[:line])]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp wildcard?(:*), do: true
  defp wildcard?([:*]), do: true
  defp wildcard?(_), do: false

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "`accept :*` accepts every public attribute — list the ones this action owns.",
      trigger: "accept",
      line_no: line_no
    )
  end
end
