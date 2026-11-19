# RegentAgentAccess

Lets a Regent Phoenix product publish its public documents to people and to
agents at the same address, and answer errors in the format the caller asked for.

- `RegentAgentAccess.negotiate/2` picks a format from `Accept` values, honouring
  quality, specificity and an explicit `q=0`.
- `RegentAgentAccess.merge_vary/1` adds `Accept` to `Vary` without dropping the
  encoding, cookie or other dimensions already there.
- `RegentAgentAccess.Plug` serves a public document's Markdown, refuses formats
  it does not have with a 406, and records the error format for `render_errors`.
- `RegentAgentAccess.Recovery` formats Markdown and JSON error bodies from the
  product's own links and hint. The JSON body is `{"error": {"code", "message", "hint"}}`.
- `RegentAgentAccess.RateLimit` counts each request against a per-client budget,
  answers with the IETF `RateLimit-Policy` and `RateLimit` headers, and past the
  budget sends 429 with `Retry-After` and the JSON error body.

The product keeps its list of public documents, its routes, policies, launch
gates and its HTML error page. Only explicitly public, database-free content
belongs in the `:documents` function; everything else reaches the router as before.

## Signed browser transport (unreleased)

`assets/signed_tools.ts` sends manifest-listed operations with their exact signed
bytes, without cookies, redirects or automatic retries. It never signs and never
sees a key: the agent's browser host does, through `window.regentsSign`.

A signed tool takes only its input. `signedTools(config).execute(name, input)`:

1. builds the exact request from the manifest and the input (method, path, body
   bytes), refusing an input the manifest does not allow;
2. hands that frozen request, `{operation, audience, origin, method, path, body?}`,
   to `window.regentsSign`, which answers `{headers}` (the proof headers for exactly
   that request) or `{error: {code, message, hint?}}`;
3. sends those same bytes with the proof headers, `credentials: "omit"` and
   `redirect: "error"`, and returns the site's `Response`.

With no `window.regentsSign` (an ordinary browser, or a host without the Regents
signer), or when the signer refuses, `execute` rejects with `Refused` before
anything is sent. Its `refusal` is `{code, message, hint}`; with no signer the code
is `agent_auth_required` and the hint names `regents browser --site <audience>`.
When the signer fails (the host went away) the code is `signer_unavailable`, and
when the call is cancelled while the signer works it is `cancelled`; nothing is sent.
Nothing unsigned is ever sent, and a browser sign-in never stands in for the agent.
Other refusals before sending are plain `Error`s whose message is the reason, such
as `missing_field:title`.

`regents browser` in regents-cli is the reference host: it runs Chromium for the
agent, records each tool call the agent makes, and signs only a request that
matches that call, the site's address and its pinned manifest.

The host supplies its configured trusted origin, audience, operation manifest and
SIWA's proof-header list, and `requestHeaders(operation)`, its own lowercase `x-`
labels for each call (ash-template names the tool and the visit, for its visit
log). Labels are never part of the proof and never authority; one that names a
proof header is refused. Product endpoints verify through SIWA once, resolve the
current pairing and enforce their own Ash policies.

Inputs use a small JSON Schema subset: `string`, `number`, `integer`, `boolean`,
`null`, `array` and `object`; `enum`; string/item/property minimum and maximum
counts; numeric `minimum`/`maximum`; and field `maxBytes` measured in UTF-8.
Arrays declare `items`. Objects declare `properties` and `required`, and reject
unknown fields. Only nested objects explicitly declaring
`additionalProperties: true` accept opaque JSON, such as report arguments;
give those fields a product limit such as `maxBytes: 8192`. Root inputs always
reject unknown fields. No values are coerced, and integers must be safe integers.
Undeclared limits are 10,000 characters per string and 100 array items or object
properties. Every preparation is bounded to depth 16 and 10,000 values; structured
request bodies cannot exceed 2,097,152 UTF-8 bytes. Endpoints retain their own
validation and authorization.

An operation that signs a complete JSON document declares its body explicitly:

```json
{
  "request_body": {"encoding": "raw_json", "field": "raw_body", "maxBytes": 2097152},
  "input_schema": {
    "type": "object",
    "properties": {"raw_body": {"type": "string"}},
    "required": ["raw_body"],
    "additionalProperties": false
  }
}
```

The raw field must contain a valid JSON object. The helper checks its size and
complexity while preserving the original text, whitespace and UTF-8 bytes for
signing and sending; it rejects text that UTF-8 conversion would change. The
declared byte limit cannot exceed 2,097,152. The raw field's default string limit
is that shared ceiling, and strings inside its document use the same ceiling.
Raw document collections use the 10,000-value ceiling rather than the typed
input default of 100 items or properties; the endpoint validates the document.
Other supplied fields must be consumed by declared string route placeholders;
none become extra body fields or headers. If `operation_id_field` is declared for
a raw operation, it names a required value inside that JSON object. The request the
host signs is frozen and is the one sent. Callers cannot supply a destination,
method or publication metadata headers, and browser cookies never confer authority.

Run `mix regent_agent_access.assets` in the host before building assets to copy
the helper into `assets/vendor/regent_agent_access/signed_tools.ts`. Keep that
generated file ignored. The reference integration is ash-template.

## Usage

```elixir
# mix.exs
{:regent_agent_access, path: Path.join(shared, "elixir-utils/agent_access")}
```

```elixir
# endpoint.ex, just before the router
plug RegentAgentAccess.Plug,
  documents: &MyAppWeb.PublicDocuments.document/1,
  guide: "/llms.txt"
```

```elixir
# config.exs
render_errors: [
  formats: [html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON, md: MyAppWeb.ErrorMD],
  layout: false
]
```

```elixir
defmodule MyAppWeb.ErrorMD do
  def render(template, _assigns) do
    template
    |> Phoenix.Controller.status_message_from_template()
    |> RegentAgentAccess.Recovery.markdown(MyAppWeb.PublicDocuments.recovery_links())
  end
end
```

```elixir
# router.ex: one budget per client address, counted by the product's own limiter
pipeline :rate_limit do
  plug RegentAgentAccess.RateLimit,
    policy: "default",
    limit: 120,
    window: 60,
    admit: &MyApp.RequestRateLimiter.admit/3,
    key: &MyAppWeb.ClientAddress.key/1
end
```

`admit` returns `{:ok, budget}` or `{:error, :rate_limited, budget}` with
`budget = %{limit: _, remaining: _, reset: _, window: _}`. A controller that
counts its own budget adds the same headers with
`RegentAgentAccess.RateLimit.put_headers(conn, policy, budget)`.

Regents is the first consumer: `platform/lib/ash_platform_web/endpoint.ex` and
`platform/lib/ash_platform_web/controllers/error_md.ex` in the Regents monorepo.

## Checks

```bash
mix check
```
