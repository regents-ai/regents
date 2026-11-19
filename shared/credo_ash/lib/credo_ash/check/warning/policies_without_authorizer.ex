defmodule CredoAsh.Check.Warning.PoliciesWithoutAuthorizer do
  @moduledoc "Reports Ash policies that have no configured policy authorizer."

  use Credo.Check,
    id: "CRA1001",
    base_priority: :higher,
    category: :warning,
    tags: [:credo_ash, :security],
    explanations: [
      check: """
      A resource with a `policies do` block but no `Ash.Policy.Authorizer` in
      its `authorizers:` list is fully open. Ash never runs the policies, so the
      module reads as protected while every action is permitted.

          # bad — policies are dead code
          use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

          policies do
            policy action_type(:read) do
              authorize_if expr(author_id == ^actor(:id))
            end
          end

          # good
          use Ash.Resource,
            domain: MyApp.Blog,
            data_layer: AshPostgres.DataLayer,
            authorizers: [Ash.Policy.Authorizer]
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.ast()
    |> CredoAsh.Resource.infos()
    |> Enum.filter(&(&1.policies_line && not &1.authorizer?))
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp issue_for(issue_meta, resource) do
    format_issue(issue_meta,
      message:
        "`#{resource.module}` declares policies but not `Ash.Policy.Authorizer` — " <>
          "the policies are ignored and the resource is unprotected.",
      trigger: "policies",
      line_no: resource.policies_line
    )
  end
end
