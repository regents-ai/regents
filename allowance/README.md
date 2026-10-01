# Regent Allowance

Each person's daily OpenAI allowance, shared by every Regent site.

A person, named by their Privy user ID, may spend $2.00 a day on OpenAI calls made
for them, counted across every site together. The day is the UTC day. Only calls made
for a person count; calls with no person attached stay under each site's own limits.

- `RegentAllowance.allowed?(privy_user_id)` — whether today's spend is under $2.00.
  Ask before a call.
- `RegentAllowance.record(privy_user_id, model, result)` — after the call, records the
  `%RegentOpenAI.Reply{}`, `%RegentOpenAI.Transcript{}` or `%RegentOpenAI.Speech{}`,
  or a `%RegentOpenAI.Error{}` OpenAI still billed. An error that was not billed
  records nothing. `model` is the model the site asked for. Returns `:ok` or
  `{:error, error}`.
- `RegentAllowance.spent_today(privy_user_id)` — today's spend in US dollars, as a
  `Decimal`.

Nothing is reserved ahead of a call, so the last call of a day can finish slightly
over the allowance. Recorded calls are money history: production refuses deleting or
emptying them.

## Adopting it on a site

Depend on it the way the site depends on `regent_payments`, with regent_openai's
`regent_http` pinned by the site:

```elixir
{:regent_allowance, git: @regents, ref: @regents_ref, sparse: "allowance"},
{:regent_openai, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "openai"},
{:regent_http, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "http", override: true}
```

Configure it with the site's repository and name:

```elixir
config :regent_allowance, repo: MySite.Repo, site: "mysite", ash_domains: [RegentAllowance]
```

Around each call made for a person:

```elixir
if RegentAllowance.allowed?(privy_user_id) do
  result = RegentOpenAI.respond(model: model, input: input)

  case result do
    {:ok, reply} -> RegentAllowance.record(privy_user_id, model, reply)
    {:error, error} -> RegentAllowance.record(privy_user_id, model, error)
  end

  result
end
```

Regents creates the `regent_allowance` schema in its release
(`RegentAllowance.Migrator`); sites never migrate it.

## Check

```bash
make check-allowance MIX_TEST_PARTITION=_mine
```
