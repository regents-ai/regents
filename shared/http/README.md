# RegentHttp

Shared Req HTTP client conventions for Regent Elixir apps: default timeouts,
request telemetry, and secret redaction in formatted errors.

## Usage

```elixir
# mix.exs
{:regent_http, path: "../elixir-utils/http"}
```

```elixir
case RegentHttp.get("https://api.example.com/things") do
  {:ok, %{status: 200, body: body}} -> {:ok, body}
  {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
  {:error, reason} -> {:error, RegentHttp.format_error(reason)}
end
```

Defaults applied to every request (overridable per call):

- `receive_timeout: 15_000`
- `connect_options: [timeout: 5_000]`

Every request emits `[:regent_http, :request]` telemetry with `%{duration}`
measurements and `%{method, host, result}` metadata.

`RegentHttp.format_error/1` and `RegentHttp.redact/1` strip bearer tokens,
`sk_live_…`/`sk_test_…`-style keys, and `x-api-key`/`authorization` header
values before anything reaches logs.

## Unexpected failures

`RegentHttp.UnexpectedFailure` logs a failure's class without its content. A site
attaches the job handler once at start and logs wherever it answers "try again":

```elixir
# application.ex
RegentHttp.UnexpectedFailure.attach_jobs()

# a controller or plug
conn |> RegentHttp.UnexpectedFailure.log(error) |> send_try_again()
```

A request line names the error's module, up to four immediate causes and a SHA-256
of the request id; a job logs once, when it gives up, never on an attempt it will
retry. Messages, bodies and job arguments are never written.

## Crash saving

`RegentHttp.ErrorSaving` keeps ErrorTracker saving crashes after one save fails. A
site that uses ErrorTracker attaches it once at start:

```elixir
# application.ex
:ok = RegentHttp.ErrorSaving.attach()
```

A save that fails, such as one that finds every database connection in use, writes
one warning line naming the exception (`Crash not saved: DBConnection.ConnectionError`)
and the next crash is saved as usual. That one crash stays off the error list.

## Addresses someone else supplied

`RegentHttp.Public.request(method, url, max_bytes: n)` (and `get/2`) call an
address a request or another site named, such as an app's published identity or
an MCP Events callback; every Regent package that does so uses it. It accepts
HTTPS only, checks that every DNS answer is a public address and connects to that
checked address (the host stays the TLS and Host name), follows no redirects, and
stops at `max_bytes` and a five-second deadline (`timeout:`). `body:` is sent with
a POST, and `answer: :headers` returns as soon as a 2xx status's headers arrive. It
emits `[:regent_http, :public_request]` with the method and result, never the host.
`config :regent_http, :public_client, Stub` replaces the network, where
`Stub.request/3` takes the same arguments.

## Adoption status

- `platform/` — adopted (replaces `PlatformPhx.ExternalHttpClient`).
- `autolaunch/` — follow-up: `lib/autolaunch/animata_holdings.ex`,
  `lib/autolaunch/erc8004.ex`, `lib/autolaunch/siwa.ex`,
  `lib/autolaunch/cca/rpc.ex` call `Req.*` directly with ad-hoc timeouts.
- `techtree/` — follow-up: `lib/tech_tree/tech.ex`,
  `lib/tech_tree/siwa_client.ex`, `lib/tech_tree/ipfs/*`,
  `lib/tech_tree/node_access/x402_batch_settlement/*`.
