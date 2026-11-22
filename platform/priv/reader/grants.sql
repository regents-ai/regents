-- What the read-only venue's login, regents_preview_reader, may read: exactly the
-- tables and columns the one site's public pages read, and nothing else (founder
-- decisions 368 a and 369 a). It gives an existing login those rights; it creates
-- no login and carries no password. Run it on the database the login reads, as a
-- login that may grant on these tables, in one go:
--
--   psql --set ON_ERROR_STOP=1 --single-transaction --file grants.sql
--
-- It is safe to run again: it first takes back every right the login holds itself
-- on this database's own schemas, then grants the list, so each run ends on the
-- list. The last step checks the outcome and, if the login could still change
-- anything here, raises and the whole run is undone. It names no database, host
-- or local detail. priv/reader/granted.sql reads back what the login holds.

-- Start from nothing the login holds itself, on every schema of this database
-- (rights everyone holds, PUBLIC's, are not the login's own and stay as they are).
DO $$
DECLARE
  area name;
BEGIN
  FOR area IN
    SELECT nspname FROM pg_namespace
    WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
      AND nspname NOT LIKE 'pg_temp_%' AND nspname NOT LIKE 'pg_toast_temp_%'
  LOOP
    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM regents_preview_reader', area);
    EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA %I FROM regents_preview_reader', area);
    EXECUTE format('REVOKE ALL ON ALL ROUTINES IN SCHEMA %I FROM regents_preview_reader', area);
    EXECUTE format('REVOKE ALL ON SCHEMA %I FROM regents_preview_reader', area);
  END LOOP;

  EXECUTE format('REVOKE ALL ON DATABASE %I FROM regents_preview_reader', current_database());
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO regents_preview_reader', current_database());
END
$$;

-- A column right is not taken back with the table's, so each is taken back by name.
DO $$
DECLARE
  granted record;
BEGIN
  FOR granted IN
    SELECT DISTINCT table_schema, table_name, column_name
    FROM information_schema.column_privileges
    WHERE grantee = 'regents_preview_reader'
  LOOP
    EXECUTE format(
      'REVOKE ALL (%I) ON TABLE %I.%I FROM regents_preview_reader',
      granted.column_name, granted.table_schema, granted.table_name
    );
  END LOOP;
END
$$;

-- Every session the login opens is read-only.
ALTER ROLE regents_preview_reader SET default_transaction_read_only = on;

-- It may not hold the database: a query is stopped after ten seconds, an open
-- transaction left idle after ten, and it keeps at most four connections (the
-- site holds three: two for pages and one listening).
ALTER ROLE regents_preview_reader SET statement_timeout = '10s';
ALTER ROLE regents_preview_reader SET idle_in_transaction_session_timeout = '10s';
ALTER ROLE regents_preview_reader CONNECTION LIMIT 4;

-- The areas it reads.
GRANT USAGE ON SCHEMA
  public, regents_app, regent_names, regent_agents, techtree_app, patchbay_app,
  keyfleet_app, autolaunch_app
  TO regents_preview_reader;

-- regents.sh's own area.
GRANT SELECT ON TABLE
  regents_app.staking_protocol_readings,
  regents_app.blog_posts,
  regents_app.paper_pro_daily_papers,
  regents_app.regents,
  regents_app.schema_migrations
  TO regents_preview_reader;

-- Whether a Regent has a cloud computer: its id and Regent only.
GRANT SELECT (id, regent_id) ON TABLE regents_app.cloud_runtimes TO regents_preview_reader;

-- The one wallet a public Regent page shows, by account id.
GRANT SELECT (id, wallet_address) ON TABLE regent_names.platform_human_users
  TO regents_preview_reader;

-- Agents' public pictures, found by the agent's wallet.
GRANT SELECT ON TABLE regent_agents.agent_pictures TO regents_preview_reader;
GRANT SELECT (id, wallet) ON TABLE regent_agents.paired_agents TO regents_preview_reader;

-- Techtree's public run log, catalog, Wallet Bench, and its applied versions.
GRANT SELECT ON TABLE
  techtree_app.catalog_releases,
  techtree_app.catalog_entries,
  techtree_app.bootstrap_releases,
  techtree_app.network_publication_entries,
  techtree_app.wallet_bench_machines,
  techtree_app.wallet_bench_payments,
  techtree_app.wallet_bench_attempts,
  techtree_app.wallet_bench_turns,
  techtree_app.wallet_bench_attempt_events,
  techtree_app.wallet_bench_version_notes,
  techtree_app.schema_migrations
  TO regents_preview_reader;

-- Autolaunch's public launch pictures (served only by UUID + SHA-256 digest).
GRANT SELECT (id, digest, content_type, byte_size, bytes) ON TABLE
  autolaunch_app.launch_draft_images,
  autolaunch_app.stock_launch_draft_images
  TO regents_preview_reader;

-- Patchbay's, Keyfleet's and Autolaunch's applied versions, for the health answer.
GRANT SELECT ON TABLE
  patchbay_app.schema_migrations,
  keyfleet_app.schema_migrations,
  autolaunch_app.schema_migrations
  TO regents_preview_reader;

-- The five helpers the site's queries call, in each form they are defined in.
GRANT EXECUTE ON FUNCTION
  public.ash_elixir_and(boolean, anycompatible),
  public.ash_elixir_and(anycompatible, anycompatible),
  public.ash_elixir_or(boolean, anycompatible),
  public.ash_elixir_or(anycompatible, anycompatible),
  public.ash_raise_error(jsonb),
  public.ash_raise_error(jsonb, anycompatible),
  public.ash_required(anycompatible, jsonb),
  public.ash_trim_whitespace(text[])
  TO regents_preview_reader;

-- The outcome: the login may change nothing here, by its own rights or by
-- everyone's. Anything else raises, and the whole run is undone.
DO $$
DECLARE
  reader oid := 'regents_preview_reader'::regrole;
  found text;
BEGIN
  SELECT string_agg(why, '; ') INTO found FROM (
    SELECT 'may sign in as a superuser, make logins or databases, copy the database or pass row rules' AS why
    FROM pg_roles
    WHERE oid = reader
      AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls)
    UNION ALL
    SELECT 'is a member of ' || pg_get_userbyid(roleid)
    FROM pg_auth_members WHERE member = reader
    UNION ALL
    SELECT 'owns ' || n.nspname || '.' || c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relowner = reader
    UNION ALL
    SELECT 'owns schema ' || nspname FROM pg_namespace WHERE nspowner = reader
    UNION ALL
    SELECT 'may create in database ' || current_database()
    WHERE has_database_privilege(reader, current_database(), 'CREATE')
    UNION ALL
    SELECT 'may create in schema ' || nspname
    FROM pg_namespace
    WHERE nspname NOT LIKE 'pg_temp_%' AND nspname NOT LIKE 'pg_toast_temp_%'
      AND has_schema_privilege(reader, oid, 'CREATE')
    UNION ALL
    SELECT 'may ' || lower(right_name) || ' ' || n.nspname || '.' || c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN unnest(ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'])
      AS rights(right_name)
    WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND has_schema_privilege(reader, n.oid, 'USAGE')
      AND has_table_privilege(reader, c.oid, right_name)
    UNION ALL
    SELECT 'may update ' || n.nspname || '.' || c.relname || '.' || a.attname
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f') AND a.attnum > 0 AND NOT a.attisdropped
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND has_schema_privilege(reader, n.oid, 'USAGE')
      AND (has_column_privilege(reader, c.oid, a.attnum, 'INSERT')
        OR has_column_privilege(reader, c.oid, a.attnum, 'UPDATE'))
    UNION ALL
    SELECT 'may run ' || p.oid::regprocedure::text || ', which runs with its owner''s rights'
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prosecdef
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND has_schema_privilege(reader, n.oid, 'USAGE')
      AND has_function_privilege(reader, p.oid, 'EXECUTE')
    UNION ALL
    SELECT 'may advance the counter ' || n.nspname || '.' || c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'S'
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND has_schema_privilege(reader, n.oid, 'USAGE')
      AND (has_sequence_privilege(reader, c.oid, 'USAGE')
        OR has_sequence_privilege(reader, c.oid, 'UPDATE'))
    UNION ALL
    SELECT 'may keep more than four connections'
    FROM pg_roles
    WHERE oid = reader AND (rolconnlimit < 0 OR rolconnlimit > 4)
  ) AS rights_to_change;

  IF found IS NOT NULL THEN
    RAISE EXCEPTION 'regents_preview_reader could still change this database: %', found;
  END IF;
END
$$;
