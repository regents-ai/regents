# Changelog

## Unreleased

- The tests are gone (19 Nov 2026), with their database and Oban, Postgrex and
  StreamData. `RegentHttp.request/1` always sends through Req: the `:client` setting
  and the `RegentHttp` behaviour, which only tests used, are gone. `:public_client`
  stays. `mix check` compiles with warnings as errors and checks unused locks,
  formatting and the usage rules.

- `RegentHttp.Public.request/3` (and `get/2`) call an address someone else
  supplied, such as an app's published identity or an MCP Events callback:
  HTTPS only, every DNS answer must be public and Mint connects to the checked
  address (the host stays the TLS name), no redirects, a byte limit and a total
  deadline; `answer: :headers` returns on a 2xx status's headers. `uri/1`,
  `valid_url?/1` and `public_ip?/1` are its checks. It emits
  `[:regent_http, :public_request]` without the host, which someone else chose.
  `Regent.MCPEvents.Callback` now uses it instead of its own copy.
  An informational (1xx) reply is skipped, never taken as the answer or as a
  callback's acknowledgement.
  A chunked reply's trailers never replace its headers. Needs Mint 1.11, whose
  HTTP/1 limits on header, status and chunk lines it relies on.

- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.
- `RegentHttp.UnexpectedFailure`, moved from the template's
  `AshTemplateWeb.UnexpectedFailure`: `log/2` writes one line for a request answered
  "try again" (the error's module, up to four immediate causes and a SHA-256 of the
  request id), and `attach_jobs/0` writes one line for each Oban job that runs out of
  attempts, from Oban's own `[:oban, :job, :exception]` event. Error messages, request
  bodies and job arguments never reach the log.
- `RegentHttp.ErrorSaving`: a site calls `attach/0` once at start, and a crash that
  ErrorTracker cannot save is one warning line instead of removing ErrorTracker's
  handler until the next restart. ErrorTracker is an optional dependency.

### Fixed

- `redact/1` also hides Anthropic API keys (`sk-ant-…`), so one can never reach a log through
  `format_error/1`.

## 0.1.0 (2026-06-10)

- Initial release: `RegentHttp.request/1`, `get/2`, `post/2` with shared
  timeout defaults, `[:regent_http, :request]` telemetry, and
  `format_error/1`/`redact/1` secret redaction. Ported from
  `PlatformPhx.ExternalHttpClient`.
