# Regents web: move to the shared Fly Postgres

Status: Step 1 (code) is on `main`; Step 2 (production) is authorised by the founder
("go right after") and runs from this document. Written 2026-09-11 from read-only
inspection of both databases.

## Where things stand

The Fly app `regents-sh-web` is the last product still on the old cluster:

| | Old (today) | Shared (target) |
| --- | --- | --- |
| Cluster | `regents-pg-test` (`nvwq9ozp9ye03kl1`) | `regents-platform-prod` (`dzx6qo6xqzvojpv5`) |
| Database | `regent_marketing_web` | `regents_prod` |
| Attached apps | `regents-sh-web`, `regent-shadow-web` | `patchbay-regents`, `platform-phx`, `autolaunch-sh`, `techtree-sh`, `autolaunch-sh-migrations` |

The committed code on `main` (commit `39d1db7` and later) already refuses the old
cluster: production boots only against `direct.dzx6qo6xqzvojpv5.flympg.net`, and
the release migrator additionally requires the secrets
`ASH_PLATFORM_DATABASE_TARGET_MODE=production`,
`ASH_PLATFORM_DATABASE_CLUSTER_ID=dzx6qo6xqzvojpv5` and
`ASH_PLATFORM_DATABASE_CLUSTER_NAME=regents-platform-prod`. **Deploying `main`
without this move would fail at the release step.** The live machine still runs
image `main-f897756`.

## What the old database holds

Only three tables have rows. Everything else Regents owns is empty.

| Table | Rows | What it is |
| --- | ---: | --- |
| `platform.platform_human_users` | 27 | Accounts created by Regents sign-ins (Privy id, wallet, display name, avatar) |
| `public.session_authorities` | 174 | Browser sign-in sessions |
| `public.account_ens_identities` | 25 | Cached ENS name and avatar per account (a cache of public chain state) |
| `public.regents`, `agent_links`, `agent_pairing_codes`, `cloud_runtimes`, `linked_identities`, `stake_redeem_operations`, `discussions.comments`, all `autolaunch.*` | 0 | |

Compared against the shared account table `regent_names.platform_human_users`
(108 rows) by hashed Privy id and hashed wallet:

- 24 of the 27 old accounts already exist in the shared table as the same person
  (same Privy id and same wallet), almost always under a different row id.
- 3 old accounts (old ids 15, 24, 69) do not exist in the shared table yet.
- Row ids collide (old ids 6, 19, 76, 78 exist in both tables), so rows can never be
  copied across by id.

Staking and redemption positions are read from Base on every visit; nothing
about them lives in either database.

## What the shared database already has for Regents

- `regent_names.platform_human_users` and the `basenames_*` tables (owned by the
  platform, read by Regents).
- `autolaunch_app.*` (owned by Autolaunch, read by Regents' Autolaunch pages).
- An empty schema `regents_app`, created for Regents' own tables, matching the
  per-product layout `autolaunch_app` / `patchbay_app` / `techtree_app` that the
  identity README prescribes.
- `public.schema_migrations` lists all 43 Regents migration versions as applied,
  but none of the tables those migrations create exist. That ledger is untrue for
  Regents and must not be relied on.

## Recommended plan: hard cutover, no data copy

Every row in the old database is either already in the shared table or is
rebuilt by normal use, so the simplest safe move is to create Regents' tables
fresh and repoint the app.

Consequences to accept, stated plainly:

1. Everyone is signed out once and signs in again with Privy (the 174 sessions are
   not carried over).
2. ENS names and avatars re-resolve on the next visit (the 25 cached rows are not
   carried over).
3. The 3 accounts not yet in the shared table are recreated on their next sign-in.
   Their Regents-side display name or avatar, if they set one, is not carried over.
4. For the 24 accounts that already exist in the shared table, the shared row's
   display name and avatar are the ones shown from now on.
5. The old cluster is left untouched as a fallback until you say otherwise.

### Step 1: code (local, tested, then committed and pushed)

- `regents_app` is the one schema for Regents' own tables everywhere: production,
  staging, development and test. It is fixed in the Repo module rather than read
  from an environment variable, because the generated migration names that schema
  in its foreign keys, so one layout has to hold in every environment.
- Regents' own resources (`session_authorities`, `account_ens_identities`,
  `linked_identities`, `regents`, `agent_links`, `agent_pairing_codes`,
  `cloud_runtimes`, `comments`) live in `regents_app`. The `comments` table drops
  its separate `discussions` schema. (`stake_redeem_operations` has no resource any
  more and is not recreated.)
- The 43 legacy migrations, which hard-coded the retired `platform`, `autolaunch`
  and `discussions` schemas, are replaced by two generated files: the Ash helper
  functions install and one baseline that creates the eight tables. The ledger for
  Regents is `regents_app.schema_migrations`, like the other three products.
- The release migrator creates the schema if needed and runs with that prefix.
  The staging bootstrap and the local fixture load `priv/repo/shared_tables.sql`,
  an idempotent copy of the tables Regents reads but does not own
  (`regent_names.platform_human_users` and the `autolaunch_app` tables), then run
  the same migrator. `mix ash.codegen --check`, the full ExUnit suite and the
  browser specs pass.
- Local databases created under the old layout (`ash_platform_dev` and every
  `ash_platform*_test`) must be dropped and recreated; the suite rebuilds a fresh
  one on its first run.

### Step 2: production (each command written out; no values printed)

Preflight, read-only:

```bash
fly auth whoami
fly mpg list --org regent
fly status -a regents-sh-web
```

Repoint the app's two database secrets at the shared database (the attach
command writes the connection string itself; nothing is printed):

```bash
fly secrets unset --stage DATABASE_POOLED_URL DATABASE_DIRECT_URL -a regents-sh-web
fly mpg attach dzx6qo6xqzvojpv5 --app regents-sh-web --database regents_prod --variable-name DATABASE_POOLED_URL
fly mpg attach dzx6qo6xqzvojpv5 --app regents-sh-web --database regents_prod --variable-name DATABASE_DIRECT_URL
```

Set the non-secret target identifiers the release migrator checks:

```bash
fly secrets set --stage ASH_PLATFORM_DATABASE_TARGET_MODE=production ASH_PLATFORM_DATABASE_CLUSTER_ID=dzx6qo6xqzvojpv5 ASH_PLATFORM_DATABASE_CLUSTER_NAME=regents-platform-prod -a regents-sh-web
```

Deploy `main` (the release step creates the `regents_app` tables, then the
machine restarts on the new configuration):

```bash
fly deploy --ha=false -a regents-sh-web
```

Verify:

```bash
fly status -a regents-sh-web
fly ssh console -a regents-sh-web -C "/app/bin/ash_platform rpc 'IO.inspect(AshPlatform.Repo.query!(~s|select schemaname, relname, n_live_tup from pg_stat_user_tables order by 1, 2|).rows, limit: :infinity)'"
```

Then a real sign-in on regents.sh, a Stake page read, and a Redeem page read.

Rollback: `fly secrets unset --stage` the three new values, re-attach the old
cluster's database, and redeploy image `main-f897756`. The old database is not
modified by any step above.

### Step 3: afterwards

- Detach and destroy `regents-pg-test` only on your explicit word (also hosts
  `regent-shadow-web`).
- Remove the untrue 43 Regents versions from the shared `public.schema_migrations`
  ledger only on your explicit word; they are harmless but misleading.

## Autolaunch tables: Regents' copy has drifted from Autolaunch's

Regents' Autolaunch pages are switched off in production
(`ASH_PLATFORM_AUTOLAUNCH_SURFACES` is not `on`), so nothing below is reachable
there today. It matters before they are ever switched on, because those pages
read and write `autolaunch_app` tables that Autolaunch owns:

- Production `autolaunch_app.launch_drafts` has no `regent_id` and no `title`
  column; Regents' launch-draft resource requires both (the "launch a token for
  my regent" flow).
- Production `autolaunch_app.auctions` requires `creator_human_account_id`, which
  Regents' auction resource does not know about.
- Production `autolaunch_app` also has tables Regents never reads
  (`human_accounts`, `session_authorities`, `linked_identities`, `x_connections`,
  `wallet_attempts`, `launch_draft_images`).

`priv/repo/shared_tables.sql` deliberately carries the shape Regents' code expects,
not production's, so the suite proves Regents against its own contract. Deciding
whether Regents keeps Autolaunch pages at all, and if so realigning its resources
to Autolaunch's schema, is a separate product decision.

## Alternative: carry the three accounts and the display names over

If you want the 3 new accounts and the 24 accounts' Regents-side display names
and avatars preserved, that is a small one-off SQL step run inside the shared
database after Step 1 and before Step 2's deploy: insert the 3 missing accounts by
Privy id, and update display name and avatar on the 24 matched rows where the
shared row has none. Sessions and the ENS cache would still be rebuilt by use.
This touches personal identifiers in production, so it needs your separate
approval and a named window.

## Decisions

1. Recommended plan approved 2026-09-11 (hard cutover, no data copy; the 208 name
   claims were already in the shared database).
2. Step 1 approved and built 2026-09-11.
3. Step 2 approved for immediately after Step 1 ("go right after").
