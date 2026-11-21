-- What the read-only venue's login, regents_preview_reader, holds on the database
-- this runs on, read back from the database itself: its sign-in rights and
-- settings, and every database, schema, table, column and function right it has,
-- by its own grants or by everyone's (PUBLIC's). It only reads. Run it as any
-- login on the database priv/reader/grants.sql was run on:
--
--   psql --set ON_ERROR_STOP=1 --file granted.sql

\echo '== Login'
SELECT rolname AS login, rolcanlogin AS can_sign_in, rolsuper AS superuser,
       rolcreaterole AS makes_logins, rolcreatedb AS makes_databases,
       rolreplication AS copies_database, rolbypassrls AS passes_row_rules,
       rolconnlimit AS connection_limit
FROM pg_roles WHERE rolname = 'regents_preview_reader';

\echo '== Member of'
SELECT pg_get_userbyid(roleid) AS member_of
FROM pg_auth_members WHERE member = 'regents_preview_reader'::regrole
ORDER BY 1;

\echo '== Settings'
SELECT coalesce(d.datname, 'every database') AS database, unnest(s.setconfig) AS setting
FROM pg_db_role_setting s LEFT JOIN pg_database d ON d.oid = s.setdatabase
WHERE s.setrole = 'regents_preview_reader'::regrole
ORDER BY 1, 2;

\echo '== Database'
SELECT current_database() AS database, right_name AS holds
FROM unnest(ARRAY['CONNECT', 'CREATE', 'TEMPORARY']) AS rights(right_name)
WHERE has_database_privilege('regents_preview_reader', current_database(), right_name)
ORDER BY 2;

\echo '== Schemas'
SELECT nspname AS schema, right_name AS holds
FROM pg_namespace CROSS JOIN unnest(ARRAY['USAGE', 'CREATE']) AS rights(right_name)
WHERE nspname NOT LIKE 'pg_temp_%' AND nspname NOT LIKE 'pg_toast_temp_%'
  AND nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
  AND has_schema_privilege('regents_preview_reader', oid, right_name)
ORDER BY 1, 2;

\echo '== Tables'
SELECT n.nspname AS schema, c.relname AS table_name, string_agg(right_name, ', ' ORDER BY right_name) AS holds
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'])
  AS rights(right_name)
WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND has_table_privilege('regents_preview_reader', c.oid, right_name)
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '== Columns (tables held by column only)'
SELECT n.nspname AS schema, c.relname AS table_name,
       string_agg(a.attname, ', ' ORDER BY a.attnum) AS readable_columns
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f') AND a.attnum > 0 AND NOT a.attisdropped
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND NOT has_table_privilege('regents_preview_reader', c.oid, 'SELECT')
  AND has_column_privilege('regents_preview_reader', c.oid, a.attnum, 'SELECT')
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '== Column writes'
SELECT n.nspname AS schema, c.relname AS table_name, a.attname AS column_name
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f') AND a.attnum > 0 AND NOT a.attisdropped
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND (has_column_privilege('regents_preview_reader', c.oid, a.attnum, 'INSERT')
    OR has_column_privilege('regents_preview_reader', c.oid, a.attnum, 'UPDATE'))
ORDER BY 1, 2, 3;

\echo '== Functions it may run, in schemas it may use'
SELECT n.nspname AS schema, p.oid::regprocedure AS function,
       p.prosecdef AS runs_as_owner,
       CASE WHEN has_function_privilege('public', p.oid, 'EXECUTE')
            THEN 'everyone' ELSE 'this login' END AS granted_to
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND has_schema_privilege('regents_preview_reader', n.oid, 'USAGE')
  AND has_function_privilege('regents_preview_reader', p.oid, 'EXECUTE')
ORDER BY 1, p.oid::regprocedure::text;

\echo '== Owns'
SELECT 'table' AS kind, n.nspname || '.' || c.relname AS name
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relowner = 'regents_preview_reader'::regrole
UNION ALL
SELECT 'schema', nspname FROM pg_namespace WHERE nspowner = 'regents_preview_reader'::regrole
UNION ALL
SELECT 'function', p.oid::regprocedure::text FROM pg_proc p
WHERE p.proowner = 'regents_preview_reader'::regrole
ORDER BY 1, 2;
