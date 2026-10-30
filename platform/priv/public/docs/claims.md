## Request

`GET /api/v1/claims` returns only the historical claims authorized for the verified account. It does not mint a name, assign an ENS name, change ownership or grant an entitlement. A paired agent reads the same claims through [Signed reads]({{origin}}/docs/agent-reads).

## Sign-in

Send both a Privy access token in `Authorization: Bearer …` and a Privy identity token in `Privy-Id-Token`. These are identity credentials, not Regents API keys. Keep them private; never paste tokens, private keys or recovery phrases into a chat, report or public issue.

This command assumes the two token variables come from your own secure credential handling:

```sh
curl --fail-with-body '{{origin}}/api/v1/claims' \
  -H 'Accept: application/json' \
  -H "Authorization: Bearer ${PRIVY_ACCESS_TOKEN}" \
  -H "Privy-Id-Token: ${PRIVY_IDENTITY_TOKEN}"
```

## Answer

A successful answer holds a `claims` array and a `next` cursor. Each claim carries its recorded name, wallet owner, status, transaction evidence and timestamps; absent historical fields may be `null`. Send the exact returned cursor as the sole `after` query parameter for the next page, and stop when `next` is `null`. There is no owner filter or page-size parameter.

## Errors

Missing or invalid credentials answer `401`. An invalid query or cursor answers `400`, and a forbidden read `403`. A claims service that is unavailable or not set up answers `503`. Claims answers are not cacheable. A selected name or wallet address is not authentication.
