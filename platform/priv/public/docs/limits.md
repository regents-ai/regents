## Budget

Each client address has 120 requests per 60 seconds, shared by `/healthz` and every `/api` address. Pairing (`POST /api/agents/v1/pair`) also counts against a `"pair"` budget of 10 a minute, since each try spends a guess at a code.

## Headers

Every answer from `/healthz` and the `/api` addresses says where you stand:

```http
RateLimit-Policy: "default";q=120;w=60
RateLimit: "default";r=119;t=42
```

`q` is the number of requests allowed in a window of `w` seconds, `r` is how many remain and `t` is the number of seconds until the window resets. A pairing answer lists the `"pair"` budget beside the default one.

## Over limit

The answer is `429` with the code `too_many_requests` and a `Retry-After` header in seconds. Wait that long, then send the request again.

## Base readings

A stake read ([Staking]({{origin}}/docs/staking), or the same through [Signed reads]({{origin}}/docs/agent-reads)) also reads Base. Each client address has 30 Base readings a minute, shared with the wallet figures the site's pages show. Past it the answer is `429` with the code `rate_limited` and a `Retry-After` header in seconds.
