# Local public API

This narrow beta-foundation checkpoint serves one anonymous, read-only operation:
`GET /api/techtree/v1/tree/nodes`.

The canonical contract is `contracts/api-contract.openapiv3.yaml`; the served copy is byte-identical at `/api-contract.openapiv3.yaml`.

No browser authentication, writes, payments, messaging, signing, runtime control, or other product API family is included in this checkpoint.

Local tests create only the protected `platform.platform_human_users` table shape needed for Techtree comment and reaction foreign keys; this scaffold is not an Accounts or authentication feature.

## Run the local checkpoint

Run these commands from the repository root. They use the fixed local test database and never read `DATABASE_URL`.

```sh
MIX_ENV=test mix ecto.create
MIX_ENV=test mix run -e 'AshPlatform.LocalDatabaseFixture.ensure_human_accounts!()'
MIX_ENV=test mix ash_platform.seed_browser_comments
MIX_ENV=test ASH_PLATFORM_BROWSER_TEST=1 mix phx.server > /tmp/ash-platform-local-api.log 2>&1 &
SERVER_PID=$!
READY=0
for _attempt in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:4002/api-contract.openapiv3.yaml >/dev/null; then READY=1; break; fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" || true; exit 1; fi
curl --fail --silent --show-error --dump-header /tmp/ash-platform-contract.headers --output /tmp/ash-platform-contract.yaml http://127.0.0.1:4002/api-contract.openapiv3.yaml
grep --ignore-case --quiet '^content-type: application/yaml' /tmp/ash-platform-contract.headers
CANONICAL_SHA=$(shasum -a 256 contracts/api-contract.openapiv3.yaml | awk '{print $1}')
SERVED_SHA=$(shasum -a 256 /tmp/ash-platform-contract.yaml | awk '{print $1}')
test "$CANONICAL_SHA" = "$SERVED_SHA"
curl --fail --silent http://127.0.0.1:4002/api/techtree/v1/tree/nodes
kill "$SERVER_PID"
wait "$SERVER_PID" || true
```

The browser fixture step is optional. Without it, the endpoint returns the seed state already present in the test database.

## Prove reset is safe and complete

The reset task is guarded: it runs only against a loopback database whose name ends in `_test`, and it removes only records matching the complete browser-fixture markers. Run it twice to prove it is repeatable, then restart the server and confirm the public collection is empty.

```sh
MIX_ENV=test mix ash_platform.reset_browser_comments
MIX_ENV=test mix ash_platform.reset_browser_comments
MIX_ENV=test ASH_PLATFORM_BROWSER_TEST=1 mix phx.server > /tmp/ash-platform-local-api.log 2>&1 &
SERVER_PID=$!
READY=0
for _attempt in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:4002/api-contract.openapiv3.yaml >/dev/null; then READY=1; break; fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" || true; exit 1; fi
BODY=$(curl --fail --silent --show-error http://127.0.0.1:4002/api/techtree/v1/tree/nodes)
test "$BODY" = '{"data":[]}'
kill "$SERVER_PID"
wait "$SERVER_PID" || true
```

The final response must be exactly `{"data":[]}`. Confirm no browser-fixture records remain:

```sh
MIX_ENV=test mix run -e 'result = Ecto.Adapters.SQL.query!(AshPlatform.Repo, "SELECT count(*) FROM techtree.nodes WHERE title IN ($1, $2)", ["Browser comment fixture", "Browser notebook fixture"]); [[0]] = result.rows; IO.puts("0")'
```

The residue query must print `0`.
