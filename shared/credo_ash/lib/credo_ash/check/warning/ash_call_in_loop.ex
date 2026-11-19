defmodule CredoAsh.Check.Warning.AshCallInLoop do
  @moduledoc "Reports direct Ash calls inside collection traversals."

  use Credo.Check,
    id: "CRA1004",
    base_priority: :high,
    category: :warning,
    tags: [:credo_ash, :performance],
    explanations: [
      check: """
      An `Ash.*` read, write or load inside an `Enum` traversal or a `for`
      comprehension issues one round trip per element. Load relationships in a
      single statement, declare an aggregate, or use a bulk action.

          # bad — one query per user
          Enum.map(users, &Ash.load!(&1, :posts))

          # good — one query for all of them
          Ash.load!(users, :posts)

          # bad — one write per row
          Enum.each(rows, &Ash.update!(&1, %{}, action: :mark_stale))

          # good
          Ash.bulk_update!(rows, :mark_stale, %{})

      Calls made through a domain code interface are not visible to this check;
      loops that call one still need review by hand.
      """
    ]

  @loops [:map, :each, :reduce, :flat_map, :filter, :reject, :find, :map_join, :with_index]
  @calls [
    :read,
    :read!,
    :read_one,
    :read_one!,
    :one,
    :one!,
    :get,
    :get!,
    :first,
    :first!,
    :create,
    :create!,
    :update,
    :update!,
    :destroy,
    :destroy!,
    :load,
    :load!,
    :count,
    :count!,
    :exists?,
    :aggregate,
    :aggregate!
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Enum]}, loop]}, meta, args} = ast,
         issues,
         issue_meta
       )
       when loop in @loops do
    {ast, issues ++ issues_for(args, meta, "Enum.#{loop}", issue_meta)}
  end

  defp traverse({:for, meta, args} = ast, issues, issue_meta) when is_list(args) do
    {ast, issues ++ issues_for(args, meta, "for", issue_meta)}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issues_for(args, meta, loop, issue_meta) do
    case ash_calls(args) do
      [] -> []
      [call | _] -> [issue_for(issue_meta, meta[:line], loop, call)]
    end
  end

  defp ash_calls(args) do
    {_ast, calls} =
      Macro.prewalk(args, [], fn
        {{:., _, [{:__aliases__, _, [:Ash]}, fun]}, _, _} = node, acc when fun in @calls ->
          {node, [fun | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp issue_for(issue_meta, line_no, loop, call) do
    format_issue(issue_meta,
      message:
        "`Ash.#{call}` runs inside `#{loop}` — one round trip per element. " <>
          "Load or write the whole collection in one call, or declare an aggregate.",
      trigger: "Ash.#{call}",
      line_no: line_no
    )
  end
end
