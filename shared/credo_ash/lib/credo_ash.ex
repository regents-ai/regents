defmodule CredoAsh do
  @moduledoc """
  Credo checks for Ash Framework anti-patterns.

  These checks encode the mechanically detectable rules from the `ash-regents`
  playbook — the ones a static analyser can decide on its own. Resource design,
  codegen discipline and whether a derived value belongs in a calculation still
  need a reader.

  ## Setup

  Add to your `.credo.exs`:

      %{configs: [%{name: "default", plugins: [{CredoAsh, []}]}]}

  If the config pins an explicit `checks.enabled` list, append the checks:

      checks: %{
        enabled: existing ++ Enum.map(CredoAsh.recommended_checks(), &{&1, []})
      }
  """

  import Credo.Plugin

  @checks [
    CredoAsh.Check.Warning.PoliciesWithoutAuthorizer,
    CredoAsh.Check.Warning.AuthorizerWithoutPolicies,
    CredoAsh.Check.Warning.UnprotectedResource,
    CredoAsh.Check.Warning.AshCallInLoop,
    CredoAsh.Check.Warning.ActorOnExecution,
    CredoAsh.Check.Warning.DirectRepoCall,
    CredoAsh.Check.Warning.UnjustifiedAuthorizeFalse,
    CredoAsh.Check.Design.WildcardAccept
  ]

  @default_config "%{configs: [%{name: \"default\", checks: %{extra: #{inspect(Enum.map(@checks, &{&1, []}))}}}]}"

  @doc false
  def init(exec), do: register_default_config(exec, @default_config)

  @doc "Every check shipped by this package."
  @spec checks() :: [module()]
  def checks, do: @checks

  @doc "The checks recommended for every Ash project — currently all of them."
  @spec recommended_checks() :: [module()]
  def recommended_checks, do: @checks
end
