# Staging venue

The staging venue is a disposable copy of the platform that exists so a release
image can be exercised before the identical image reaches production. It owns its
own database, `regents-staging-db`, and nothing in it is a source of truth.

This guide covers the deployment role, the one-time database bootstrap, the
migration listing, the ordering of the first deploy, the steps that create the
venue and who runs each, its secrets, deploying a candidate to it, promoting that
exact image to production, rolling production back, what staging shares with
production, what it does not reproduce, and recovery.

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

Regents reads `regent_names.platform_human_users` and the `autolaunch_app` tables
but does not own them: no migration in this repository creates them. Staging has
no upstream copy, so the first staging database needs those tables created before
migrations can run.

`bin/bootstrap-staging` does that once, on an empty database:

1. It refuses unless `ASH_PLATFORM_DEPLOYMENT_ROLE` is exactly `staging`, before it
   opens any connection.
2. It resolves its target through the same release configuration the migrate
   command uses, which under the staging role can only be a staging host.
3. It refuses, and changes nothing, if the database already has a
   `regents_app.schema_migrations` table or a `regent_names` schema.
4. Otherwise it creates the shared tables from `priv/repo/shared_tables.sql`,
   with the same shape the local fixture uses, then runs every migration into the
   `regents_app` schema.

The tables it creates are staging-only approximations of tables owned outside this
repository. They are deliberately the shape the whole local test suite already
runs on, and nothing else.

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
digest for both the bootstrap machine and the deploy.

The image is built here, offline, and pushed by hand. Fly's remote builder is not
used: it fetches from the network during the build, which is exactly what this
repository's sealed supply exists to avoid, and it archives its own view of the
build context rather than the one `Dockerfile.dockerignore` describes.

The sealed build resolves nothing over the network, so it only completes on a
machine that already holds the four pinned base images and the app stage's
`apt-get` layer. Warm a cold machine by running the same build once online —
`docker build --platform linux/amd64 -f <context>/Dockerfile -t warm <context>` —
and then run the sealed build, which reuses what that left in the daemon's store.
The assembly script leaves out env-shaped files itself and refuses to publish a
context that holds one. Still list the context before an upload: the script can
vouch for it only up to the moment it hands it over, never for anything that
lands in it afterwards.

```sh
# 1. Assemble the sealed build context. It nests this checkout under
#    <context>/ash-platform, so no command below runs from the context root.
scripts/build-release-context.sh <context> amd64

# 2. Build it locally and offline, the command the script itself prints, tagged
#    for the staging registry with the candidate's commit sha. Any directory.
docker build --network=none --pull=false --platform linux/amd64 \
  -f <context>/Dockerfile -t registry.fly.io/regents-staging:<candidate-sha> <context>

# 3. Push it, then read back the digest the registry assigned. That digest, not
#    the tag, is what every later step names. An image can carry a digest for
#    every repository it was ever pushed to, so ask for the Fly one by name
#    rather than taking the first; the digest: line docker push prints is the
#    same value.
fly auth docker
docker push registry.fly.io/regents-staging:<candidate-sha>
docker inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' \
  registry.fly.io/regents-staging:<candidate-sha> \
  | grep '^registry\.fly\.io/regents-staging@'

# 4. Bootstrap the empty database from that exact digest, in a throwaway machine.
#    fly machine run applies no [env] from any config file, and the role is not a
#    secret on staging, so the machine is told its role on the command line. The
#    BEAM release plus migrations needs more than Fly's 256 MB default.
fly machine run registry.fly.io/regents-staging@sha256:<digest> \
  --app regents-staging --rm --vm-memory 1024 \
  --env ASH_PLATFORM_DEPLOYMENT_ROLE=staging -- /app/bin/bootstrap-staging

# 5. Release the same digest. From the repository root, where fly.staging.toml
#    is; --image builds nothing, so no build context is involved.
fly deploy -a regents-staging -c fly.staging.toml \
  --image registry.fly.io/regents-staging@sha256:<digest> --ha=false
```

Building once and naming the digest at every later step is what makes staging a
review of the artifact that production will receive, rather than of a rebuild.

Later deploys run exactly these steps without the bootstrap; see
[Deploying a candidate](#deploying-a-candidate). Migrations run through
`bin/migrate` in the release command, as they do in production.

## Creating the venue

These steps run once, in this order. The Web-ops manager builds the venue with
flyctl; the founder personally supplies the values only he holds, the Privy origin,
and anything that touches production. Each step below says which.

1. **Manager.** `fly apps create regents-staging` in org `regent`.
2. **Manager.** `fly postgres create --name regents-staging-db --region iad`
   (smallest single node) and `fly postgres attach regents-staging-db -a
   regents-staging`, then set `DATABASE_POOLED_URL` and `DATABASE_DIRECT_URL` to
   that URL.
3. **Manager, then founder.** The rest of the secrets, per [Secrets](#secrets):
   the manager sets the ones it generates or already knows (`SECRET_KEY_BASE`,
   `PHX_HOST`, the surface flags); the founder sets the ones whose values only he
   holds. Nothing is copied from production: `fly secrets list` shows names and
   digests, never values.
4. **Manager, and the founder for DNS.** `fly certs add staging.regents.sh -a
   regents-staging`. The certificate is the manager's; the DNS record it prints is
   the founder's whenever the registrar is outside our tooling.
5. **Founder.** The Privy origin for `staging.regents.sh`. Staging shares
   production's Privy app, so this is an edit to production's Privy configuration
   (see [What staging shares with production](#what-staging-shares-with-production)).
6. **Manager.** The first deploy, per [First deploy](#first-deploy), then open a
   database-backed page — `/app` signed out, then `/autolaunch` — in addition to
   `/healthz`. `/healthz` is static and never touches the database, so it alone
   does not prove the venue works.
7. **Founder.** At this venue's own production deploy, which is the first promote
   that carries the `[env]` role line: run
   `fly secrets unset ASH_PLATFORM_DEPLOYMENT_ROLE -a regents-sh-web --stage`
   immediately before `fly deploy -a regents-sh-web -c fly.toml --image <digest>`,
   so the role moves from the staged secret to `[env]` in that one deploy. Verify
   with `fly config env -a regents-sh-web` afterwards.

`fly.toml` in this repository is the truth for the production role. The secret of
the same name staged on `regents-sh-web` is only the stopgap that covers the window
before the `[env]` line ships, and step 7 retires it.

## Secrets

Staging carries every production runtime flag at its production value. The manager
sets the surface flags — `ASH_PLATFORM_APP_SURFACES`,
`ASH_PLATFORM_AUTOLAUNCH_SURFACES`, `ASH_PLATFORM_REGENTS_CLUB_METADATA_CUTOVER`.
The founder sets the ones whose values only he holds: `PRIVY_APP_ID`,
`PRIVY_VERIFICATION_KEY`, `BASE_READ_RPC_URL`, and the Regents Club attestations
`ASH_PLATFORM_REGENTS_CLUB_PRIVY_ORIGIN_CANARY` and
`ASH_PLATFORM_REGENTS_CLUB_MEDIA_FULL_CORPUS_SHA256`.

Three are staging's own, and all three are the manager's:

- `SECRET_KEY_BASE` — newly generated for staging, at least 64 bytes. Production's
  is never copied.
- `PHX_HOST` — `staging.regents.sh`.
- `DATABASE_POOLED_URL` and `DATABASE_DIRECT_URL` — both the attached
  `regents-staging-db.flycast` URL.

`ASH_PLATFORM_DATABASE_CLUSTER_ID`, `ASH_PLATFORM_DATABASE_CLUSTER_NAME`, and
`ASH_PLATFORM_DATABASE_TARGET_MODE` are not set on staging. They exist for the
production rehearsal ceremony, which the staging role never enters.

The deployment role itself is not a secret on staging: `fly.staging.toml` carries
`ASH_PLATFORM_DEPLOYMENT_ROLE = "staging"` in `[env]`.

## Deploying a candidate

There is one deploy procedure, in [First deploy](#first-deploy): assemble the
context, build it locally and offline, push it, and deploy that digest with
`--image`. A later deploy is those steps with the bootstrap left out — the
database already exists — and nothing else differs.

After the deploy, record the full reference from `fly image show -a regents-staging`
on the ticket. That reference, digest included, is the candidate's identity for the
rest of the review: a rebuild produces a different digest and is a different
candidate.

## Promoting to production

Promotion deploys the byte-identical image staging reviewed. It is a production
deploy, so it happens only after the founder has tested the candidate on staging
and said to proceed.

Two preconditions, both recorded on the ticket first:

1. **No pending migrations.** `fly deploy --image` still runs `/app/bin/migrate` on
   production, so a candidate may only be promoted when its migration set equals
   the set production has already applied. Confirm with `bin/pending-migrations`
   against production; `none` is the only output that permits a promote.
2. **The rollback target.** The current production image reference from
   `fly image show -a regents-sh-web`, recorded before anything changes.

The pending-migration check reads production's database. That is founder data
access on every promote, not a routine lane step: the founder runs it himself,
inside his own test window, from a one-off machine started on the candidate image
so the command exists and inherits production's secrets. The machine is told its
role on the command line for the same reason the bootstrap machine is: `fly machine
run` applies no `[env]` from any config file, and by this point the staged role
secret on `regents-sh-web` is gone. It needs production's memory ceiling too:

```sh
fly machine run registry.fly.io/regents-staging@sha256:<digest> \
  --app regents-sh-web --rm --vm-memory 1024 \
  --env ASH_PLATFORM_DEPLOYMENT_ROLE=production -- /app/bin/pending-migrations
```

Never run it from production's running release. On the first promote that release
does not carry the command at all, and on later ones it is the old image rather
than the candidate.

The database it reads is production's exact target,
`direct.nvwq9ozp9ye03kl1.flympg.net`, cluster `nvwq9ozp9ye03kl1`, which is named
`regents-pg-test` despite serving production. That name is not reconciled here;
`docs/production/fly-mpg-cutover-and-restore.md` owns the cluster's replacement.

With both preconditions recorded, promote from the repository root, where
`fly.toml` is. `--image` builds nothing, so the assembled context plays no part.
**Founder.** This is a production deploy, his the same way step 7 of
[Creating the venue](#creating-the-venue) is:

```sh
fly deploy -a regents-sh-web -c fly.toml \
  --image registry.fly.io/regents-staging@sha256:<digest>
```

Evidence that production received the reviewed artifact:
`fly image show -a regents-sh-web` reports the same `sha256:` as staging.

A candidate that adds a migration is not promotable through staging. It goes
through `docs/production/fly-mpg-cutover-and-restore.md` as its own founder-gated
action, and that document's hard NO-GO on production DDL still stands.

Standing rule: never destroy or rename `regents-staging` while production
references its registry repository. Production's running image lives at
`registry.fly.io/regents-staging@sha256:…`, and destroying the app that owns that
repository would strip production of the image it redeploys from.

## Rolling production back

**Founder.** A rollback is a production deploy too, his the same way the promote
is. From the repository root, so `[env] ASH_PLATFORM_DEPLOYMENT_ROLE =
"production"` in `fly.toml` goes back onto the machines with it:

```sh
fly deploy -a regents-sh-web -c fly.toml --image <full previous reference>
```

This is code only. It does not undo a migration; a database that has moved forward
needs `docs/production/fly-mpg-cutover-and-restore.md`, not a rollback deploy.

One case needs a step first. Rolling back to an image that predates this venue's
own production deploy means running a release that requires the deployment role
while the `[env]` line may not be in the `fly.toml` being deployed — `[env]` comes
from the file the deploy command is given, not from the image. Re-stage the secret
before that deploy:

```sh
fly secrets set ASH_PLATFORM_DEPLOYMENT_ROLE=production -a regents-sh-web --stage
```

## What staging shares with production

- **The Privy identity realm.** Staging uses production's Privy app id and
  verification key, so a token minted at `staging.regents.sh` verifies against
  production's key, and adding that origin is a change to production's Privy
  configuration. Sessions still do not cross: the `_ash_platform_key` cookie is
  host-only, so `staging.regents.sh` and `regents.sh` cannot exchange one.
- **The chain.** `contracts/base-mainnet.json`, chain 8453, is baked into the
  image and `BASE_READ_RPC_URL` points at Base mainnet. Staging is therefore
  chain-identical to production: any Stake, Redeem, or Autolaunch action performed
  on staging is a real mainnet transaction, spending real value, under the
  founder's ordinary per-action signing authority. There is no testnet here and
  nothing on staging makes a transaction a rehearsal.
- **Nothing through `DATABASE_URL`.** `fly postgres attach` leaves a `DATABASE_URL`
  secret behind. No code reads it: `test/ash_platform_web/boundary_test.exs` fails
  if any file under `config/`, `lib/`, or `rel/` contains the literal text
  `System.get_env("DATABASE_URL")`, which is how this repository would read it.
  The database staging reaches is the one `DATABASE_POOLED_URL` and
  `DATABASE_DIRECT_URL` name, and the staging role admits only staging hosts.

## What staging does not reproduce

Production runs two machines and the release does not cluster them: `mix.exs`
carries neither `libcluster` nor `dns_cluster`, so a `Phoenix.PubSub` broadcast on
production reaches only the sessions connected to the machine that sent it.
Staging runs a single machine, which never splits, so every session there sees
every broadcast.

A candidate whose behavior depends on one session's action reaching another —
anything driven by a broadcast rather than by the acting session's own reply — can
therefore pass on staging and misbehave on production. Such a candidate needs a
production-shaped check:

1. Scale staging to production's topology for the check —
   `fly scale count 2 -a regents-staging`, and back to `1` afterwards.
2. Read the two machine ids from `fly machine list -a regents-staging`.
3. Pin each browser session to a different machine with the
   `fly-force-instance-id: <machine id>` request header, which Fly's proxy honours
   for the page load and the LiveView socket that follows it. Set it with a
   request-header browser extension, or drive the two sessions from a scripted
   browser that can.
4. Exercise the flow across the two pinned sessions.

Without the pinning both sessions can land on the same machine, where every
broadcast arrives and the check proves nothing.

## Recovery

The staging database is disposable and holds nothing anyone needs. That is the
whole recovery story:

- **A bootstrap failed partway.** Destroy and recreate the staging database, then
  run `bin/bootstrap-staging` again. Do not try to finish a partial bootstrap by
  hand; the command refuses a database that already carries migration state or the
  `regent_names` schema precisely so a half-finished state cannot be papered over.
- **A migration failed on staging.** Read `bin/pending-migrations` to see exactly
  where the database stopped, fix the migration in the repository, and deploy a new
  image. If the database is too far out of shape to reason about, destroy and
  recreate it and bootstrap again.
- **`bin/pending-migrations` says `no schema_migrations table`.** The database was
  never bootstrapped, or was recreated since. Run `bin/bootstrap-staging`.
- **The venue is wedged for any other reason.** Recreating the database and
  redeploying the current image is always available and always cheap.
