defmodule CredoAsh.Check.Warning.AuthorizerWithoutPolicies do
  @moduledoc "Reports Ash resources that declare an authorizer without policies."

  use Credo.Check,
    id: "CRA1002",
    base_priority: :higher,
    category: :warning,
    tags: [:credo_ash, :security],
    explanations: [
      check: """
      A resource that declares `Ash.Policy.Authorizer` but has no `policies do`
      block forbids every action. Ash is fail-closed, so nothing is authorized
      and the resource silently stops working for every caller.

          # bad — every action returns Forbidden
          use Ash.Resource,
            domain: MyApp.Blog,
            data_layer: AshPostgres.DataLayer,
            authorizers: [Ash.Policy.Authorizer]

          # good — add the block the authorizer expects
          policies do
            policy action_type(:read) do
              authorize_if always()
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
    |> Enum.filter(&(&1.authorizer? && is_nil(&1.policies_line)))
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp issue_for(issue_meta, resource) do
    format_issue(issue_meta,
      message:
        "`#{resource.module}` declares `Ash.Policy.Authorizer` but has no `policies do` block — " <>
          "every action is forbidden.",
      trigger: "authorizers",
      line_no: resource.line
    )
  end
end
