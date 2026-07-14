# Local public API

The canonical contract is `contracts/api-contract.openapiv3.yaml`. Run
`mix ash_platform.sync_api_contract` after changing it, and
`mix ash_platform.sync_api_contract --check` to verify the served copy.

`GET /api/techtree/v1/tree/nodes` is an anonymous public read. It returns the
six contract fields for every public node, newest first. Pagination: none.
Query parameters are not supported.

## Local test fixture lifecycle

The browser proof uses two deterministic records in the local test database. The seed and reset
commands are safe to repeat. Reset refuses every environment except `MIX_ENV=test`, every
non-loopback database host, and every database name that does not end in `_test`.

From `/Users/sean/Documents/regent/ash-platform`, prepare the local test database:

```sh
MIX_ENV=test mix ash_platform.setup_local_auth
```

Seed the browser records, then start the test server:

```sh
MIX_ENV=test mix ash_platform.seed_browser_comments
MIX_ENV=test ASH_PLATFORM_BROWSER_TEST=1 mix phx.server
```

The test server binds only to `127.0.0.1:4002`. In another terminal, verify the public response,
record its content hash, and prove that the served contract has the expected content type and is
byte-identical to the canonical contract:

```sh
curl --fail --silent --show-error http://127.0.0.1:4002/api/techtree/v1/tree/nodes | tee /tmp/ash-platform-public-nodes.json
shasum -a 256 /tmp/ash-platform-public-nodes.json
curl --fail --silent --show-error --dump-header /tmp/ash-platform-contract.headers --output /tmp/ash-platform-served-contract.yaml http://127.0.0.1:4002/api-contract.openapiv3.yaml
grep -i '^content-type: application/yaml' /tmp/ash-platform-contract.headers
shasum -a 256 contracts/api-contract.openapiv3.yaml /tmp/ash-platform-served-contract.yaml
```

Stop the server, remove only the records owned by this browser proof, and confirm that no public
nodes remain. Running reset a second time must also succeed.

```sh
MIX_ENV=test mix ash_platform.reset_browser_comments
MIX_ENV=test mix ash_platform.reset_browser_comments
MIX_ENV=test ASH_PLATFORM_BROWSER_TEST=1 mix phx.server
curl --fail --silent --show-error http://127.0.0.1:4002/api/techtree/v1/tree/nodes
```

The final response for a clean local test database is:

```json
{"data":[]}
```
