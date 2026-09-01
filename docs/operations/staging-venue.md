# Staging venue

The staging venue is a disposable copy of the platform that exists so a release
image can be exercised before the identical image reaches production. It owns its
own database, `regents-staging-db`, and nothing in it is a source of truth.

This guide covers the deployment role, the one-time database bootstrap, the
migration listing, the ordering of the first deploy, and recovery.

## Deployment role

Every production-mode boot must say which venue it is. `AshPlatform.DatabaseConfig`
reads `ASH_PLATFORM_DEPLOYMENT_ROLE` and accepts exactly two values:

| Role | Database hosts it will accept |
| --- | --- |
| `production` | `direct.nvwq9ozp9ye03kl1.flympg.net` |
| `staging` | `regents-staging-db.flycast` or `regents-staging-db.internal` |

There is no default and no fallback between the two. A missing or unrecognized
value stops the boot before any database URL is read, so a deployment that forgets
to name itself fails closed instead of guessing.

Under the staging role the configuration refuses, on both the serving path and the
release path, any `flympg.net` host, the production database host, the production
cluster id `nvwq9ozp9ye03kl1`, and every production application identity, wherever
they appear in the URL — host, database name, or credentials. The rehearsal-mode
ceremony that guards production migrations does not apply to staging, because the
staging role can only ever reach the staging database.

The development and test environments never read the role.

## Bootstrap

The platform reads `platform.platform_human_users` but does not own it: no
migration in this repository creates it. Staging has no upstream copy, so the
first staging database needs that table created before migrations can run.

`bin/bootstrap-staging` does that once, on an empty database:

1. It refuses unless `ASH_PLATFORM_DEPLOYMENT_ROLE` is exactly `staging`, before it
   opens any connection.
2. It resolves its target through the same release configuration the migrate
   command uses, which under the staging role can only be a staging host.
3. It refuses, and changes nothing, if the database already has a
   `schema_migrations` table or a `platform` schema.
4. Otherwise it creates the `platform` schema and `platform.platform_human_users`
   with the same shape the local fixture uses, then runs every migration.

The table it creates is a staging-only approximation of a table owned outside this
repository. It is deliberately the shape the whole local test suite already runs
on, and nothing else.

The command never repairs. If it fails partway, recover by destroying and
recreating the staging database (see [Recovery](#recovery)).

## Listing pending migrations

`bin/pending-migrations` reports what a deployed database and the release image
disagree about. It reads only: it applies nothing, creates nothing, and takes no
migration lock.

It prints, in order:

- `pending:` followed by every migration version the release carries that the
  database has not applied.
- `applied-without-file:` followed by every version the database has applied whose
  migration file the release does not carry.
- `none` when both lists are empty.

`none` is the only output that means the image and the database agree.

If the database has no `schema_migrations` table at all — a fresh staging database
before its bootstrap — the command fails with the message
`no schema_migrations table: run bootstrap-staging first` and exits nonzero, so an
absent table can never be mistaken for agreement. It fails by raising, so the exit
carries an Elixir error report and a stack trace around that message rather than
one bare line.

This is the only staging command that may also be run against production, and only
as founder data access inside the founder's own window.

## First deploy

The staging app has no image in its registry until something pushes one, so the
bootstrap cannot run before the first build. Build once, then reuse that exact
digest for both the bootstrap machine and the deploy:

```sh
# 1. Build and push the image without releasing it, then record the digest.
fly deploy --build-only --push -a regents-staging -c fly.staging.toml

# 2. Bootstrap the empty database from that exact image, in a throwaway machine.
#    The BEAM release plus migrations needs more than Fly's 256 MB default.
fly machine run registry.fly.io/regents-staging@sha256:<digest> \
  --app regents-staging --rm --vm-memory 1024 -- /app/bin/bootstrap-staging

# 3. Release the same digest.
fly deploy -a regents-staging -c fly.staging.toml \
  --image registry.fly.io/regents-staging@sha256:<digest> --ha=false
```

Building once and naming the digest at every later step is what makes staging a
review of the artifact that production will receive, rather than of a rebuild.

Subsequent deploys need only step 3; migrations run through `bin/migrate` as they
do in production.

## Recovery

The staging database is disposable and holds nothing anyone needs. That is the
whole recovery story:

- **A bootstrap failed partway.** Destroy and recreate the staging database, then
  run `bin/bootstrap-staging` again. Do not try to finish a partial bootstrap by
  hand; the command refuses a database that already carries migration state or the
  `platform` schema precisely so a half-finished state cannot be papered over.
- **A migration failed on staging.** Read `bin/pending-migrations` to see exactly
  where the database stopped, fix the migration in the repository, and deploy a new
  image. If the database is too far out of shape to reason about, destroy and
  recreate it and bootstrap again.
- **`bin/pending-migrations` says `no schema_migrations table`.** The database was
  never bootstrapped, or was recreated since. Run `bin/bootstrap-staging`.
- **The venue is wedged for any other reason.** Recreating the database and
  redeploying the current image is always available and always cheap.
