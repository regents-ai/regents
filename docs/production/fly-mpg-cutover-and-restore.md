# Fly Managed Postgres Cutover and Restore Plan

## Purpose and authority

This is an operator plan for rehearsing and, only after separate approval, executing the `ash-platform` database cutover. It is not status tracking, a migration approval, or a new source of product ownership. No production contact, database change, backup, restore, credential change, deploy, traffic change, or Fly action is authorized by this plan.

The controlling sources remain:

- `/Users/sean/Documents/regent/founder.md` and `/Users/sean/Documents/regent/metaprogramming/stack.yaml` for stack ownership, source-of-truth order, protected data, and signed-value rules;
- `/Users/sean/Documents/regent/.agents/skills/regent-workflow/references/current-stack.md` for the current product and database ownership map;
- `docs/ASH-PLATFORM-DIRECTIVES.md` for the accepted `ash-platform` candidate boundaries and the four protected datasets;
- current Ash resources and their generated snapshots for intended table mappings; and
- current source-generated migrations for the exact proposed database change.

Platform retains ownership of human identity, billing, Formation, and shared public Regent records. Techtree and Autolaunch retain ownership of their product workflow state. Ash maps deliberately onto those owned tables; it does not acquire ownership by recreating them. Existing production tables must not be recreated, destructively rewritten, or rebuilt by replaying old migrations.

## Protected production invariants

The following are the current verified production invariants. A preflight, rehearsal, cutover, restore, or rollback is invalid if any value differs without a separately approved and explained production change:

| Protected table | Required row count |
| --- | ---: |
| `platform.platform_human_users` | 107 |
| `platform.basenames_mints` | 208 |
| `platform.basenames_mint_allowances` | 398 |
| `platform.basenames_payment_credits` | 35 |

Counts alone are not sufficient. Each gate below also requires a protected structural fingerprint and an ordered content hash so that a restore cannot pass after silent row or schema drift.

## Current hard NO-GO

Production DDL is currently a hard **NO-GO**.

`priv/repo/migrations/20260711174345_create_techtree_trees_and_nodes.exs` is source-generated but unconditionally creates `techtree.nodes`. That table already exists in production under different current truth. Running this migration against production would create a catalog collision and cannot be treated as an acceptable failure mode.

The source-generated migration strategy must be corrected from current Ash resource and production catalog truth, then fully rehearsed against a separate cluster restored from the exact candidate production backup. Do not hand-edit production around the conflict and do not mark the migration as applied without proving its full intended effect.

The correction also needs explicit answers to two ownership questions before production DDL can be considered:

1. What is the complete Autolaunch parallel-state and catalog census, including tables, schemas, indexes, constraints, grants, sequences, and current data owners?
2. Which migration history owns every existing Platform, Techtree, and Autolaunch object, and which histories are dispositioned rather than replayed?

XMTP and old-platform unknowns do not block unrelated engineering work. They also cannot be used as authority to approve a production migration.

## Prerequisites before a rehearsal may start

All items must be complete and evidenced:

1. The `.25.1` pooled/direct configuration is complete: the running application uses the approved pooled connection and the release migrator uses the approved direct connection. The two roles are tested independently without printing either connection value.
2. The disposable `regents-pg-test` cluster is replaced. Its system `fly-user` has no supported in-place credential rotation, so the exposed credential must become invalid through replacement, not reuse. The replacement must have a new identity and newly issued credentials held only in the approved secret manager or operator passfile.
3. An empty-cluster rehearsal succeeds first, proving bootstrap order, extensions, schemas, grants, migrations, and application startup without relying on pre-existing objects.
4. Integrated Platform and Regents CLI tests pass against a public test endpoint, including health, readiness, public endpoint behavior, and the applicable doctor checks.
5. The exact commit and deployable artifact are frozen. Record immutable commit and image/artifact identifiers; do not rebuild between rehearsal and the proposed production window.
6. The migration artifact is generated from the final Ash resource truth, is clean under the repository's generation check, and has been reviewed line by line against the restored catalog.

## Engineering rehearsal and restore-proof gates

Engineering may prepare and execute local or explicitly disposable rehearsal work without production contact. Production backup and restore proof are protected operations with a narrow approval sequence. This section does not authorize any action by itself.

### Gate 1: identity-only preflight

Confirm the operator account, organization, intended application, and cluster identity without retrieving or displaying credentials. Safe Fly commands are limited here to official identity and non-secret list surfaces:

```bash
export REGENT_FLY_ORG='<approved-org-slug>'
fly auth whoami
fly apps list --org "$REGENT_FLY_ORG"
fly mpg list --org "$REGENT_FLY_ORG"
```

Before using these commands, verify from the installed Fly CLI's official documentation that their output fields contain no connection URLs, passwords, tokens, or private credential material. Stop if the output contract is uncertain. Do not use interactive database or detailed status subcommands, or any command known to print a URL or password.

Record only the operator identity, organization, application name, cluster name/id, region, attachment relationship, and observation time. Do not record credentials or connection strings.

### Gate 2: frozen package and backup/restore-only approval

Complete the non-production prerequisites, freeze the exact commit, deployable artifact, migration artifact, and migration checksum, and finish the identity-only preflight. Before any production database connection or query, the Chief must grant a bounded approval naming only the production backup and its restore into a new disposable cluster. It must name the application, source cluster and immutable id, frozen identifiers, backup window, operators, stop conditions, and new restore target. It does not authorize a database connection, fingerprint query, migration, deploy, traffic change, or any write other than the managed backup and separate restore operations.

An unfilled field means no approval:

```text
Chief backup/restore-only approval
Application: <exact Fly application>
Source production cluster: <exact name and immutable id>
Frozen commit: <full commit id>
Frozen artifact: <immutable image/artifact id>
Migration artifact: <path and checksum>
Backup window: <start, end, and timezone>
New disposable restore target: <exact new name and region>
Primary operator: <name>
Second operator/reviewer: <name>
Approved actions: <create/verify one full backup; restore that exact backup to the named new target>
Prohibited actions: <database connection/query, migration, deploy, traffic/configuration change, production write>
Stop conditions: <explicit conditions>
Approval by Chief: <name and timestamp>
```

### Gate 3: completed full backup

Create the candidate backup only during an explicitly authorized rehearsal or production operation. List backups using only the installed Fly CLI's officially supported, non-secret Managed Postgres backup surface:

```bash
export REGENT_MPG_CLUSTER_ID='<approved-cluster-id>'
fly mpg backups list "$REGENT_MPG_CLUSTER_ID"
```

Before use, verify the exact syntax and output fields against the installed CLI's official documentation. Stop if the command would print credentials or connection information. A backup gate passes only when the backup is completed, has a recorded immutable identifier and completion time, belongs to the expected cluster, and its restore eligibility has been confirmed.

`backup_1783879042_762ca54d47958a7f` is the pre-reset **TEST** backup for the old test cluster `nvwq9ozp9ye03kl1`. It is not a production backup and can never satisfy a production cutover gate.

### Gate 4: restore the exact backup separately and prove the restored copy

Restore the exact candidate backup into a new, separate disposable cluster. Never restore over production and never reuse the old test cluster. The restore action requires its own explicit authorization and must name the source backup and new target cluster.

Connect only to the restored disposable cluster, using the credential-safe fingerprint procedure below. Before any production database connection or query, prove from the restored copy alone:

- all four protected counts are exactly `107`, `208`, `398`, and `35` respectively;
- all required schemas, tables, columns, types, nullability, defaults, constraints, indexes, extensions, sequences, ownership, current sequence values, raw ACLs, grants, role memberships, server major version, relevant settings, and schema-only dump are observable and internally sane;
- every protected table has a deterministic complete-row multiset hash; and
- every explicitly inventoried and approved Ecto, Ash, and old Platform migration-history table has an exact-content hash, without replaying any old history;
- application roles have only their intended grants.

Any missing object, unexpected count, unapproved migration-history table, insufficient privilege, unreadable catalog field, failed hash, or other anomaly is a failed restore gate. Investigate the backup or fingerprint; do not normalize the restored copy. Only after this gate passes may the Chief consider a separate production read-only comparison approval.

### Gate 5: separately authorized source-versus-restored equality

The Chief must separately authorize one bounded, read-only production fingerprint query. The approval must name the production source, restored target, exact reviewed fingerprint procedure and checksum, sufficiently privileged read-only audit role, operators, time window, expected evidence fields, and stop conditions. It does not authorize migration, DDL, deploy, traffic change, or any production write.

Run the identical credential-safe fingerprint procedure against production and the untouched restored copy. Compare the resulting hashes and counts, never raw rows. The production source and restored copy must match for every required catalog section, migration-history inventory and exact contents, protected count and content multiset hash, server major version and relevant setting, and schema-only dump. A difference or unobservable field is a failed gate.

#### Credential-safe fingerprint procedure

Use a secret-manager-generated `PGSERVICE` entry and a permission-restricted passfile. The service must select a read-only audit role with enough catalog visibility and `SELECT` access to every inventoried relation and sequence. Do not place a URL or password in an argument, enable shell tracing, print environment variables, or capture raw command output in the evidence package. Run the complete block in `zsh`; do not translate it to `/bin/sh`. The `fingerprint` wrapper sends canonical output directly to `shasum`, captures producer diagnostics without displaying them, withholds the digest until the complete producer pipeline succeeds without any diagnostic output, and removes both temporary files before returning. Record only its labeled digest.

Set `PGSERVICE` and `PGPASSFILE` through the approved operator environment, then run the following unchanged for source and restore. `PGOPTIONS` enforces a read-only session. A non-zero command, warning, permission error, null sequence value, missing expected row, or unobservable field aborts the gate.

```zsh
set -euo pipefail

fingerprint() {
  local label="$1" digest_file stderr_file digest result=1
  shift
  digest_file="$(mktemp "${TMPDIR:-/tmp}/regent-fingerprint.XXXXXX")" || return 1
  stderr_file="$(mktemp "${TMPDIR:-/tmp}/regent-fingerprint-stderr.XXXXXX")" || {
    rm -f "$digest_file"
    return 1
  }

  if "$@" 2>"$stderr_file" | shasum -a 256 >"$digest_file" && [[ ! -s "$stderr_file" ]]; then
    digest="$(<"$digest_file")"
    result=0
  fi

  rm -f "$digest_file" "$stderr_file"
  (( result == 0 )) || return 1
  printf '%s  %s\n' "$label" "$digest"
}

export PGSERVICE='<approved-read-only-audit-service>'
export PGPASSFILE='<permission-restricted-passfile-path>'
export PGOPTIONS='-c default_transaction_read_only=on'

fingerprint settings psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
SELECT name || E'\t' || setting
FROM pg_settings
WHERE name IN ('server_version_num', 'block_size', 'server_encoding',
               'lc_collate', 'lc_ctype', 'max_identifier_length',
               'standard_conforming_strings')
ORDER BY name;
SELECT 'server_major' || E'\t' || current_setting('server_version_num')::integer / 10000;
SQL

fingerprint relations psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
WITH relation_fingerprint(row_text) AS (
  SELECT 'column' || E'\t' || n.nspname || E'\t' || c.relname || E'\t' || a.attnum || E'\t' ||
         a.attname || E'\t' || pg_catalog.format_type(a.atttypid, a.atttypmod) || E'\t' ||
         a.attnotnull || E'\t' || COALESCE(pg_get_expr(d.adbin, d.adrelid), '<NULL>')
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f') AND a.attnum > 0 AND NOT a.attisdropped
  UNION ALL
  SELECT 'relation' || E'\t' || n.nspname || E'\t' || c.relname || E'\t' || c.relkind || E'\t' ||
         pg_get_userbyid(c.relowner) || E'\t' || COALESCE(c.relpersistence::text, '<NULL>') || E'\t<NULL>\t<NULL>'
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
)
SELECT row_text
FROM relation_fingerprint
ORDER BY row_text;
SQL

fingerprint constraints psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
SELECT n.nspname, c.relname, con.conname, con.contype, con.condeferrable,
       con.condeferred, con.convalidated, pg_get_constraintdef(con.oid, true)
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname, con.conname;
SQL

fingerprint indexes psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
SELECT n.nspname, t.relname, i.relname, x.indisunique, x.indisprimary,
       x.indisvalid, x.indisready, pg_get_indexdef(i.oid)
FROM pg_index x
JOIN pg_class t ON t.oid = x.indrelid
JOIN pg_class i ON i.oid = x.indexrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
ORDER BY n.nspname, t.relname, i.relname;
SQL

fingerprint extensions psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
SELECT e.extname, e.extversion, n.nspname, pg_get_userbyid(e.extowner)
FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;
SQL

fingerprint sequences psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
SELECT n.nspname, c.relname, pg_get_userbyid(c.relowner),
       s.seqstart, s.seqincrement, s.seqmax, s.seqmin, s.seqcache, s.seqcycle,
       COALESCE(dn.nspname || '.' || dc.relname || '.' || a.attname, '<UNOWNED>')
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_sequence s ON s.seqrelid = c.oid
LEFT JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = c.oid
                     AND d.refclassid = 'pg_class'::regclass AND d.deptype IN ('a', 'i')
LEFT JOIN pg_class dc ON dc.oid = d.refobjid
LEFT JOIN pg_namespace dn ON dn.oid = dc.relnamespace
LEFT JOIN pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname;
SELECT format(
  'SELECT %L, %L, last_value, is_called FROM %I.%I;',
  n.nspname, c.relname, n.nspname, c.relname
)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
  AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname
\gexec
SQL

fingerprint privileges psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
SELECT 'database' AS object_type, datname AS object_name,
       pg_get_userbyid(datdba) AS owner_name, COALESCE(datacl::text, '<NULL>') AS acl_text
FROM pg_database WHERE datname = current_database()
UNION ALL
SELECT 'schema', nspname, pg_get_userbyid(nspowner), COALESCE(nspacl::text, '<NULL>')
FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname <> 'information_schema'
UNION ALL
SELECT CASE c.relkind WHEN 'S' THEN 'sequence' ELSE 'relation' END,
       n.nspname || '.' || c.relname, pg_get_userbyid(c.relowner), COALESCE(c.relacl::text, '<NULL>')
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
UNION ALL
SELECT 'function', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_userbyid(p.proowner), COALESCE(p.proacl::text, '<NULL>')
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
UNION ALL
SELECT 'role-membership', pg_get_userbyid(m.roleid) || '->' || pg_get_userbyid(m.member),
       COALESCE(pg_get_userbyid(m.grantor), '<NULL>'), m.admin_option::text
FROM pg_auth_members m
ORDER BY object_type, object_name, owner_name, acl_text;
SQL

fingerprint protected-counts psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
SELECT 'platform.platform_human_users' AS table_name, count(*) AS row_count FROM platform.platform_human_users
UNION ALL SELECT 'platform.basenames_mints', count(*) FROM platform.basenames_mints
UNION ALL SELECT 'platform.basenames_mint_allowances', count(*) FROM platform.basenames_mint_allowances
UNION ALL SELECT 'platform.basenames_payment_credits', count(*) FROM platform.basenames_payment_credits
ORDER BY table_name, row_count;
SQL

fingerprint protected-human-users psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" -c \
  "SELECT to_jsonb(t)::text FROM platform.platform_human_users t ORDER BY to_jsonb(t)::text"
fingerprint protected-basenames-mints psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" -c \
  "SELECT to_jsonb(t)::text FROM platform.basenames_mints t ORDER BY to_jsonb(t)::text"
fingerprint protected-mint-allowances psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" -c \
  "SELECT to_jsonb(t)::text FROM platform.basenames_mint_allowances t ORDER BY to_jsonb(t)::text"
fingerprint protected-payment-credits psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" -c \
  "SELECT to_jsonb(t)::text FROM platform.basenames_payment_credits t ORDER BY to_jsonb(t)::text"

fingerprint schema-only-dump pg_dump --dbname="service=$PGSERVICE" --schema-only --no-comments \
  --restrict-key=regent_schema_fingerprint_v1
```

The frozen PostgreSQL client must support `--restrict-key`; verify that option in its installed `pg_dump --help` before either fingerprint. `regent_schema_fingerprint_v1` is fixed control text for the dump's `\restrict` and `\unrestrict` lines, not a password, token, or authentication value. Using this same explicit key for source and restore prevents `pg_dump` from inserting a random key into otherwise identical schema output. A changed key or a client without this option aborts the gate.

The complete-row hashes deliberately sort canonical JSON text rather than guessing a primary-key or column order. They therefore fingerprint the content multiset, preserve duplicates, include nulls and every current column, and remain independent of physical row order.

Migration history requires a two-pass review. Continue in the same protected `zsh` session so the fail-closed `fingerprint` wrapper remains defined. First, hash the candidate inventory without exposing it in the evidence stream:

```zsh
fingerprint migration-inventory psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
SELECT n.nspname, c.relname
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND (c.relname ~* '(schema_)?migrations|migration_history|ash.*migration'
       OR n.nspname IN ('platform', 'techtree', 'autolaunch') AND c.relname ~* 'migration')
ORDER BY n.nspname, c.relname;
SQL
```

A reviewer must inspect that inventory through an approved non-recorded channel, identify every Ecto/Ash and old Platform history table, and sign an exact schema/table allowlist. Replace the placeholders below only with that approved list; an unfilled or incomplete list aborts the gate. The generated statements hash exact complete rows in canonical JSON order and do not replay any history:

```zsh
fingerprint approved-migration-history psql -XAt --set=ON_ERROR_STOP=1 --no-psqlrc service="$PGSERVICE" <<'SQL'
WITH approved(schema_name, table_name) AS (
  VALUES
    ('<approved-schema-1>', '<approved-history-table-1>'),
    ('<approved-schema-2>', '<approved-history-table-2>')
)
SELECT format(
  'SELECT %L, to_jsonb(t)::text FROM %I.%I t ORDER BY to_jsonb(t)::text;',
  schema_name || '.' || table_name, schema_name, table_name
)
FROM approved
ORDER BY schema_name, table_name;
\gexec
SQL
```

These procedures depend on stable PostgreSQL catalog semantics and sufficiently broad read visibility. A role unable to observe raw ACL arrays, role memberships, function ACLs, sequence values, settings, or any protected/history row is not sufficient. Do not substitute `information_schema` grant views, infer missing values, weaken the query, or accept a partial digest. Record tool and server versions with the evidence so source and restore use compatible clients.

### Gate 6: catalog collision and migration review

On the untouched restored copy, census every object in the `platform`, `techtree`, and `autolaunch` schemas, plus extensions and migration-history tables. Compare that census with every operation in the exact frozen migration artifact.

The audit must explicitly classify each proposed object as new, deliberately mapped existing state, or prohibited collision. It must resolve the existing `techtree.nodes` conflict and the Autolaunch parallel-state/catalog questions. Review the exact generated migration artifact, its source snapshots, and its checksum. A newly generated or changed artifact invalidates the rehearsal.

### Gate 7: migrate only the restored rehearsal

Run the frozen migration artifact only against the restored disposable cluster through the direct migration service. Prove that the running application connects through the pooled runtime service and that migration tooling connects through the direct service. Neither proof may display credentials or URLs.

After migration, repeat the protected count, ordered-hash, schema, index, constraint, grant, and sequence fingerprint. All protected results must remain identical. No old migration may be replayed and no protected table may be recreated or rewritten.

### Gate 8: complete application validation

Against the migrated rehearsal cluster and frozen application artifact, pass all of the following:

- full backend compile, test, migration-generation, and repository acceptance checks;
- full frontend unit and integration checks;
- browser checks for the approved critical journeys and reasonable failure cases;
- public health and readiness checks;
- Platform and Regents CLI public endpoint and doctor checks;
- pooled runtime and direct migration separation checks; and
- a database scan proving no fixtures, synthetic users, test launches, test trees/nodes, rehearsal markers, or other test residue remain.

Record exact commands, versions, artifact identifiers, results, and timestamps. A partial suite or unexplained failure is a failed gate.

### Gate 9: rollback rehearsal

Rehearse recovery without running destructive down migrations. The database rollback path is a restore into a new cluster followed by an explicitly approved traffic/configuration rollback. Prove the restored cluster's protected counts, hashes, catalog fingerprint, health, readiness, backend, frontend, browser, and CLI gates before considering recovery viable.

Do not use migration `down` functions, drop tables, rewrite protected data, or switch traffic as an improvised incident action.

## Later authorized production operator actions

Engineering completion stops after the rehearsal evidence package is reviewed. Production execution is a separate protected operation. The Chief must give an explicit gate that names the exact application, production cluster, frozen commit/artifact, completed production backup, maintenance window, primary operator, second operator/reviewer, migration artifact checksum, stop conditions, and approved rollback target.

Use this approval template; an unfilled field means no approval:

```text
Chief production execution approval
Application: <exact Fly application>
Production cluster: <exact name and immutable id>
Frozen commit: <full commit id>
Frozen artifact: <immutable image/artifact id>
Migration artifact: <path and checksum>
Completed production backup: <immutable backup id and completion time>
Window: <start, end, and timezone>
Primary operator: <name>
Second operator/reviewer: <name>
Approved actions: <identity check, backup verification, migration, validation, traffic action>
Stop conditions: <explicit conditions>
Rollback target: <new restored cluster and prior traffic target>
Approval by Chief: <name and timestamp>
```

Only after that approval may the named operators perform these production actions in order:

1. freeze unrelated deploys and writes as the approved window requires;
2. confirm identity, application, cluster, artifact, migration checksum, and completed backup;
3. capture the protected pre-migration fingerprint;
4. run the rehearsed migration once through the direct connection;
5. run the full named validation gates through the pooled runtime path;
6. compare protected counts, hashes, and structural fingerprints; and
7. either declare the approved cutover complete or stop and execute the separately approved rollback.

The first unexpected result is a stop condition. Do not repair production interactively, regenerate a migration, replay an old migration, or change the frozen artifact inside the window.

## Rollback rule

Rollback never uses destructive down migrations. Under explicit approval, restore the named pre-cutover backup to a new cluster, prove fingerprint equality and application readiness there, and roll traffic/configuration back to the approved healthy target. Preserve the failed cluster for investigation unless the approval explicitly says otherwise. Cluster destruction, credential changes, and data reconciliation are separate protected actions.

## Evidence package and decision

The final rehearsal package must contain only non-secret evidence:

- source citations and the resolved ownership/migration-history decisions;
- frozen commit, application artifact, and migration checksum;
- operator identity and target names/ids;
- protected restored-copy counts and hashes, the separately authorized Gate 5 production-source counts and hashes, their source-versus-restored equality result, and the rehearsal post-migration and post-rollback counts and hashes;
- for any later production execution package, the protected pre-migration fingerprint and its post-migration equality result;
- structural fingerprints and catalog collision disposition;
- completed backup and separate restore identifiers;
- pooled/direct separation proof;
- exact validation commands and results;
- fixture-residue scan result;
- rollback rehearsal result; and
- a signed go/no-go decision.

Until every gate passes and the Chief supplies the fully named production execution approval, the decision remains **NO-GO**. This plan itself authorizes no execution.
