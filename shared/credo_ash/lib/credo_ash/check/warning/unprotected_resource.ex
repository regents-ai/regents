defmodule CredoAsh.Check.Warning.UnprotectedResource do
  @moduledoc "Reports persisted Ash resources that declare no authorization boundary."

  use Credo.Check,
    id: "CRA1003",
    base_priority: :high,
    category: :warning,
    tags: [:credo_ash, :security],
    explanations: [
      check: """
      A persisted resource with neither an authorizer nor policies is reachable
      by any actor. Every user-accessible resource needs both.

      Embedded resources (`data_layer: :embedded`) are projections held inside a
      parent record and are authorized by that parent, so they are not flagged.

          # bad
          use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

          # good
          use Ash.Resource,
            domain: MyApp.Blog,
            data_layer: AshPostgres.DataLayer,
            authorizers: [Ash.Policy.Authorizer]

          policies do
            policy action_type(:read) do
              authorize_if expr(published)
            end
          end
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.ast()
    |> CredoAsh.Resource.infos()
    |> Enum.filter(&unprotected?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp unprotected?(resource) do
    resource.data_layer != :embedded and not resource.authorizer? and
      is_nil(resource.policies_line)
  end

  defp issue_for(issue_meta, resource) do
    format_issue(issue_meta,
      message:
        "`#{resource.module}` has no authorizer and no policies — " <>
          "every action is open to every actor.",
      trigger: "Ash.Resource",
      line_no: resource.line
    )
  end
end
