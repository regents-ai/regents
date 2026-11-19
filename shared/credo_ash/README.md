# credo_ash

Credo checks for Ash Framework anti-patterns.

Generic Elixir linters are blind to Ash. Credo core knows nothing about
resources or policies, and [ExSlop](https://github.com/elixir-vibe/ex_slop)'s
database checks only fire on modules literally named `Repo` — so on an Ash
codebase its two most valuable checks find nothing and report clean.

This package fills that gap. It encodes the rules from the `ash-regents`
playbook that a static analyser can decide on its own. The rules that need
judgment — resource design, codegen discipline, whether a derived value belongs
in a calculation — stay with a reviewer.

## Checks

| Check | Catches |
|-------|---------|
| `Warning.PoliciesWithoutAuthorizer` | A `policies do` block with no `Ash.Policy.Authorizer` — policies are dead code and the resource is open |
| `Warning.AuthorizerWithoutPolicies` | An authorizer with no policies — Ash is fail-closed, so every action is forbidden |
| `Warning.UnprotectedResource` | A persisted resource with neither (embedded resources are exempt) |
| `Warning.AshCallInLoop` | `Ash.*` reads, writes or loads inside `Enum` traversals and `for` comprehensions — the Ash-shaped N+1 |
| `Warning.ActorOnExecution` | `actor:` passed to the executing call instead of `for_read/3` or `for_action/4` |
| `Warning.DirectRepoCall` | `Repo` calls that bypass policies, changes and notifications (raw SQL is exempt; a comment explaining the bypass clears it) |
| `Warning.UnjustifiedAuthorizeFalse` | `authorize?: false` with no comment saying why |
| `Design.WildcardAccept` | `accept :*` |

## Installation

```elixir
{:credo_ash, path: "../elixir-utils/credo_ash", only: :dev, runtime: false}
```

Register it in `.credo.exs`:

```elixir
%{configs: [%{name: "default", plugins: [{CredoAsh, []}]}]}
```

If your config pins an explicit `checks.enabled` list, append the checks
instead — a plugin's defaults are ignored when the list is explicit:

```elixir
checks: %{
  enabled: [
    # ...existing checks...
  ] ++ Enum.map(CredoAsh.recommended_checks(), &{&1, []})
}
```

## Known limits

- Calls made through a domain code interface (`Blog.list_posts!/1`) are
  indistinguishable from any other function call, so loops around one are not
  detected. Only direct `Ash.*` calls are.
- `Warning.ActorOnExecution` fires on the deliberate system-actor idiom
  (`Ash.create(changeset, actor: @actor)`). That is by design — the actor is
  still invisible to changes and validations that ran during `for_action/4` —
  but on a codebase that uses the idiom widely, expect to triage a batch of
  them at once.
