## 2026-10-30

The contact page is gone. Its help, privacy, legal and security addresses are in the Contact section of [About]({{origin}}/about), and the `regents_about` browser tool no longer takes `contact`.

The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) list the check-in refusal for an unpaired agent as `403 agent_not_paired`, as the site answers, and list `400 invalid_name` among the pairing refusals. They are now version 4.0.1.

The developer docs are one page per topic under `/docs`, and each answers `Accept: text/markdown` at its own address. The `regents_about` browser tool reads each docs page by its own name, such as `docs-pairing`; `docs` is the overview.

## 2026-10-28

The browser tool list moved from `/capabilities` to [/capabilities.json]({{origin}}/capabilities.json), and now also gives `build`: the `commit` and `release` this site runs, as on the other Regents sites. The check-in command is `regents protocol agents status`, formerly `agents me`. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 4.0.0.

## 2026-10-20

`GET /api/v1/health` answers the health check as JSON, `{"status": "ok"}`, as on the other Regents sites. The [OpenAPI JSON specification]({{origin}}/openapi.json) is now version 3.1.0.

One request limit covers `/healthz` and every `/api` address: 120 requests a minute for each client address, with pairing also held to 10 a minute. Past a limit the code is `too_many_requests` instead of `rate_limited`, and check-ins no longer have a separate budget of 60. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 3.0.0.

## 2026-09-28

Every error, including sign-in refusals, pages that aren't open yet and the product, claims, stake and agent reads, answers `{"error": {"code": "…", "message": "…", "hint": "…"}}`. The codes are unchanged. The [OpenAPI JSON specification]({{origin}}/openapi.json) and the [YAML contract]({{origin}}/api-contract.openapiv3.yaml) are now version 2.0.0.
