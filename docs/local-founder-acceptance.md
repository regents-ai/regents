# Local founder acceptance

This foundation creates one disposable PostgreSQL database on this Mac. It uses only `127.0.0.1`, the PostgreSQL role matching the current macOS user, and a database named `ash_platform_acceptance_<run_id>`. Choose a new lowercase run ID for every run.

The supported tools are Erlang/OTP 28, Elixir 1.19.5, Node 25.8.0, npm 11.11.0, PostgreSQL 14.20 or newer, and Playwright 1.61.1. The checkout also requires an adjacent `elixir-utils` checkout at commit `cbb09857065069590671e2cbabdd5ae0885a65c4`, because the locked Privy dependency is loaded from `../elixir-utils/privy`.

From a clean checkout, setup is one command:

```sh
bin/setup-local-acceptance founder_local_001
```

The setup checks the adjacent dependency commit, local tools, and remote deployment or database settings before creating anything. It fetches locked backend dependencies, invokes the guarded setup task, installs locked browser packages, creates the unique database, runs the checked-in migrations, seeds the five committed Techtree roots, and builds the browser assets. Its initial baseline records every applied migration version, the root count and content fingerprint, and zero counts for nodes, notebooks, comments, and reactions. It does not load `.env`, `.env.local`, or `.envrc`. The lower-level `MIX_ENV=test mix ash_platform.setup_local --run-id <run-id>` command is for debugging only.

Always remove the run database when finished. Running reset again is safe:

```sh
bin/reset-local-acceptance founder_local_001
bin/reset-local-acceptance founder_local_001
```

Reset verifies the immutable run, database, and local-role ownership marker while allowing ordinary disposable product activity. It requires every protected dataset mirror to be absent or empty before deleting only that run database. It also removes generated browser assets. If the target, marker, environment, host, role, name, or protected row count is unexpected, the command stops without deleting it.
