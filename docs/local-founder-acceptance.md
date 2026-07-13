# Local founder acceptance

This foundation creates one disposable PostgreSQL database on this Mac. It uses only `127.0.0.1`, the PostgreSQL role matching the current macOS user, and a database named `ash_platform_acceptance_<run_id>`. Choose a new lowercase run ID for every run.

The supported tools are Erlang/OTP 28, Elixir 1.19.5, Node 25.8.0, npm 11.11.0, PostgreSQL 14.20 or newer, and Playwright 1.61.1. The checkout also requires an adjacent `elixir-utils` checkout at commit `cbb09857065069590671e2cbabdd5ae0885a65c4`, because the locked Privy dependency is loaded from `../elixir-utils/privy`.

From a clean checkout:

```sh
export ASH_PLATFORM_ACCEPTANCE_RUN_ID=founder_local_001
test "$(git -C ../elixir-utils rev-parse HEAD)" = cbb09857065069590671e2cbabdd5ae0885a65c4
mix deps.get
MIX_ENV=test mix ash_platform.setup_local --run-id "$ASH_PLATFORM_ACCEPTANCE_RUN_ID"
```

The setup checks the local tools before creating anything, rejects remote deployment or database settings, installs the locked browser packages, creates the unique database, runs the checked-in migrations, seeds the five committed Techtree roots, and builds the browser assets. Its baseline marker records every applied migration version, the root count and content fingerprint, and zero counts for nodes, notebooks, comments, and reactions. It does not load `.env`, `.env.local`, or `.envrc`.

Always remove the run database when finished. Running reset again is safe:

```sh
MIX_ENV=test mix ash_platform.reset_local --run-id "$ASH_PLATFORM_ACCEPTANCE_RUN_ID"
MIX_ENV=test mix ash_platform.reset_local --run-id "$ASH_PLATFORM_ACCEPTANCE_RUN_ID"
```

Reset verifies the ownership and exact baseline markers, confirms the disposable `platform_human_users` scaffold remains empty, and confirms the other three protected dataset names are absent before deleting only that run database. It also removes generated browser assets. If the target, marker, environment, host, role, name, baseline, or protected row count is unexpected, the command stops without deleting it.
