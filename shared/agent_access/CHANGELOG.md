# Changelog

## Unreleased

- The signed tools' Node test file is gone (19 Nov 2026). `mix check` compiles with
  warnings as errors and checks formatting and the usage rules.

- Signed browser tools take only their input. `signedTools(config).execute(name,
  input)` builds the exact request, asks the agent's browser host to sign it through
  `window.regentsSign`, and sends those same bytes with the returned proof headers.
  `prepare` and the `{input, request, proof}` shape are gone, so no key, receipt or
  signature passes through a tool's arguments. With no host signer, or when it
  refuses, nothing is sent and `execute` rejects with `Refused`
  (`agent_auth_required` names `regents browser --site <audience>`). A host moves
  to this shape in one step: register `{input}` tools and call `execute(name, input)`.
  A signer that fails rejects with `Refused` `signer_unavailable`, and a call
  cancelled while the signer works rejects with `Refused` `cancelled`; neither sends
  anything, so a host never reports either as an unknown outcome.

- `signedTools` takes a required `requestHeaders(operation)`: the host's own
  lowercase `x-` labels for each signed call, sent beside the proof and never part
  of it. A label that is not a lowercase `x-` name, names a proof header or holds a
  line break is refused with `invalid_request_header` before anything is sent. A
  host passes `() => ({})` for none. ash-template sends `x-regent-client` and
  `x-regent-visit` for its visit log.

- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.

## 0.2.0

- `RegentAgentAccess.RateLimit`: a plug that counts each request against a
  per-client budget kept by the product's own limiter and answers with the IETF
  `RateLimit-Policy` and `RateLimit` headers. Past the budget it sends 429 with
  `Retry-After` and the JSON error body. `put_headers/3` adds the same headers
  from a controller. The header format comes from Patchbay's `RateLimitHeaders`
  and the budget shape from Regents' `RateLimiter`.
- `RegentAgentAccess.Recovery.json/2` returns `%{error: %{code, message, hint}}`,
  Autolaunch's error document, instead of `%{errors: %{detail, code, hint}}`.
  A product's JSON error pages change shape when it moves its pin.

## 0.1.0

- Initial release: `Accept` negotiation, `Vary` merging, `RegentAgentAccess.Plug`
  for public-document Markdown and error formats, and `RegentAgentAccess.Recovery`
  for Markdown and JSON error bodies. Regents is the first consumer.
