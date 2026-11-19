defmodule CredoAsh.Check.Warning.ActorOnExecution do
  @moduledoc "Reports actors supplied after an Ash query or changeset was prepared."

  use Credo.Check,
    id: "CRA1005",
    base_priority: :normal,
    category: :warning,
    tags: [:credo_ash, :security],
    explanations: [
      check: """
      The actor belongs on the query or changeset while it is being prepared,
      not on the call that runs it. Changes, validations and preparations run
      during `for_read/3` and `for_action/4`; an actor supplied only at
      execution time is invisible to all of them.

          # bad — preparations ran without an actor
          Post
          |> Ash.Query.for_read(:feed, %{})
          |> Ash.read!(actor: actor)

          # good
          Post
          |> Ash.Query.for_read(:feed, %{}, actor: actor)
          |> Ash.read!()

      Only the two-argument form is reported, where the first argument is a
      query or changeset that was already built. When a resource module or a
      record is passed with params — `Ash.create!(Post, params, actor: actor)`,
      `Ash.update!(post, params, actor: actor)` — Ash builds the changeset from
      those same options, so the actor is present the whole time and there is
      nothing to fix.
      """
    ]

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
    :count,
    :count!,
    :exists?
  ]

  @builders [
    :for_read,
    :for_create,
    :for_update,
    :for_destroy,
    :for_action
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.ast()
    |> expand_pipes()
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
  end

  # A piped call carries only the arguments written inside its own parentheses,
  # so `row |> Ash.update!(params, actor: actor)` would otherwise look like the
  # two-argument form. Rewriting every pipe into an ordinary call first means
  # one rule covers both spellings.
  defp expand_pipes(ast) do
    Macro.prewalk(ast, fn
      {:|>, _, [left, right]} = node ->
        try do
          Macro.pipe(left, right, 0)
        rescue
          ArgumentError -> node
        end

      node ->
        node
    end)
  end

  defp traverse({{:., _, [{:__aliases__, _, [:Ash]}, fun]}, meta, args} = ast, issues, issue_meta)
       when fun in @calls do
    if late_actor?(args) do
      {ast, issues ++ [issue_for(issue_meta, meta[:line], fun)]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # Only `Ash.fun(query_or_changeset, opts)`. Anything with params in between
  # hands Ash the actor before it builds the changeset, and a bare resource
  # module does the same for a query.
  defp late_actor?([{:__aliases__, _, _}, _opts]), do: false

  defp late_actor?([subject, opts]) when is_list(opts) do
    Keyword.has_key?(opts, :actor) and skipped_preparation?(subject)
  end

  defp late_actor?(_), do: false

  # The defect is a preparation step that was denied the actor, so there has to
  # be a preparation step to blame. A query assembled from `Ash.Query.new/2` and
  # a filter runs no preparations at all, and an actor at execution is the only
  # place it could go.
  defp skipped_preparation?(subject) do
    {_ast, builders} =
      Macro.prewalk(subject, [], fn
        {{:., _, [_module, fun]}, _, args} = node, acc when fun in @builders ->
          {node, [Enum.any?(args, &(is_list(&1) and Keyword.has_key?(&1, :actor))) | acc]}

        node, acc ->
          {node, acc}
      end)

    builders != [] and not Enum.any?(builders)
  end

  defp issue_for(issue_meta, line_no, fun) do
    format_issue(issue_meta,
      message:
        "`actor:` is passed to `Ash.#{fun}` at execution — move it to the " <>
          "`for_read/3` or `for_action/4` call so preparations and changes can see it.",
      trigger: "actor",
      line_no: line_no
    )
  end
end
