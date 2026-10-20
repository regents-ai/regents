defmodule Regents.Release do
  @moduledoc false

  @app :regents
  @deployment_role_variable "REGENTS_DEPLOYMENT_ROLE"
  @staging_role "staging"
  @platform_schema "regent_names"
  @bootstrap_role_error "bootstrap-staging requires #{@deployment_role_variable} to be exactly staging"
  @missing_migration_table_error "no schema_migrations table: run bootstrap-staging first"

  @table_exists """
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relname = $2 AND c.relkind IN ('r', 'p')
  )
  """
  @schema_exists "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = $1)"

  # Every shared library with its own schema and ledger, in the order their
  # changes apply: Credits' pairing grants build on Agents' pairing history.
  @shared [
    {:regent_identity, "regent_identity", RegentIdentity.Migrator},
    {:regent_agents, "regent_agents", RegentAgents.Migrator},
    {:regent_credits, "regent_credits", RegentCredits.Migrator},
    {:regent_points, "regent_points", RegentPoints.Migrator},
    {:regent_payments, "regent_payments", RegentPayments.Migrator}
  ]

  def migration_config!(getenv \\ &System.get_env/1) do
    Regents.DatabaseConfig.release_config!(getenv)
  end

  def migrate do
    with_release_repo([], fn repo ->
      require_signed_access_schema!(repo)
      repo.migrate!(migrations_path())
    end)
  end

  @doc """
  Applies the shared database changes this release's pinned libraries carry
  that the database has not applied, and prints each one, or `none`. Run as
  `/app/bin/migrate-shared`.

  Every site carries this same command. A deployment never runs it: `migrate/0`
  refuses while a shared change is missing and applies none. Each change needs
  the founder's own named go; the site whose release first carries it runs this
  from the new image before that deployment, because only that image carries
  the change's file. Each library's ledger takes a migration lock, so two sites
  running it at once apply each change once. Its options are the bootstrap's.
  """
  def migrate_shared(opts \\ []) when is_list(opts) do
    applied =
      with_release_repo(opts, fn repo ->
        unapplied = unapplied_shared_migrations(repo)
        if unapplied != [], do: apply_shared(repo)
        unapplied
      end)

    case applied do
      [] -> IO.puts("none")
      applied -> IO.puts("applied: #{Enum.join(applied, ", ")}")
    end
  end

  @doc "Read-only release prerequisite; shared migrations require separate founder authority."
  def require_signed_access_schema!(repo) do
    :ok = require_shared_migrations!(repo)
    :ok = RegentAgents.Migrator.require_pairing_history!(repo)
    RegentCredits.Migrator.require_pairing_grants!(repo)
  end

  @doc """
  Saves paper.md and its cover from one folder. Run as `/app/bin/put-paper <folder>`.
  """
  def put_paper(folder), do: save_paper(Regents.PaperProDaily.PaperFile.read!(folder))

  @doc """
  Saves one paper on /paper-pro-daily from its two files on this machine,
  replacing it if the same paper is already on that day (`Regents.PaperProDaily.PaperFile`).
  Run as `/app/bin/put-paper <YYYY-MM-DD>.md <picture>`.
  """
  def put_paper(paper_path, picture_path) do
    save_paper(Regents.PaperProDaily.PaperFile.read!(paper_path, picture_path))
  end

  defp save_paper(attributes) do
    paper =
      with_release_repo([], fn _repo ->
        attributes
        |> Regents.PaperProDaily.put_paper!(actor: %Regents.Actors.System{})
      end)

    IO.puts("Paper Pro Daily #{paper.date}: \"#{paper.title}\" saved.")
  end

  @doc "Saves post.md and its cover using /app/bin/put-post <folder>. The slug identifies the post."
  def put_post(folder) do
    attributes = Regents.Blog.PostFile.read!(folder)
    # Render before saving so a malformed body never replaces a readable post.
    RegentBlog.markdown(attributes.markdown)

    post =
      with_release_repo([], fn _repo ->
        Regents.Blog.put_post!(attributes, actor: %Regents.Actors.System{})
      end)

    IO.puts("Article #{post.slug}: \"#{post.title}\" saved.")
  end

  @doc """
  Prepares an empty staging database for the first deployment.

  Staging owns a disposable database, so it has no copy of the tables this
  repository reads but does not own, `regent_names.platform_human_users`. This
  command creates a staging-only approximation of it with the shape the local
  fixture already proves sufficient, then applies every shared change this
  release carries, as `migrate_shared/0` does in production, and runs every
  migration into `regents_app` (`prepare_database!/2`).

  It refuses any database that already carries migration state or the
  regent_names schema, and it repairs nothing: recovery from a half-finished
  bootstrap is to destroy and recreate the staging database.

  The deployed launcher passes no options, so it reads only the database the
  release configuration resolves. The options (`:getenv`, `:config`,
  `:migrations_path`) aim it at a disposable database under test.
  """
  def bootstrap_staging(opts \\ []) when is_list(opts) do
    getenv = Keyword.get(opts, :getenv, &System.get_env/1)

    # The role is read before anything opens a connection, so no configuration
    # mistake can point this command at a database outside staging.
    if getenv.(@deployment_role_variable) != @staging_role do
      raise @bootstrap_role_error
    end

    with_release_repo(opts, fn repo ->
      refuse_existing_state!(repo)
      prepare_database!(repo, migrations_directory(opts))
    end)
  end

  @doc false
  # Staging's first deployment and every local database
  # (`Regents.LocalDatabaseFixture`) are prepared the same way, in production's
  # order: the tables this repository reads but does not own (the fixture is the
  # only definition of their shape), every shared change this release carries,
  # then this site's own migrations.
  def prepare_database!(repo, path \\ migrations_path()) do
    Regents.LocalDatabaseFixture.create_shared_tables!()
    apply_shared(repo)
    repo.migrate!(path)
  end

  @doc """
  Lists what a deployed database and the release disagree about.

  Prints every migration the release carries that the database has not applied
  under `pending:`, every version the database has applied whose file the
  release does not carry under `applied-without-file:`, and every shared change
  `migrate_shared/0` would apply under `shared-pending:` (each as schema and
  version; a deployment is refused while one is listed). Prints `none` when all
  three are empty. It applies nothing, creates nothing, and takes no migration
  lock. Its options are the bootstrap's.
  """
  def pending_migrations(opts \\ []) when is_list(opts) do
    {pending, applied_without_file, shared} =
      with_release_repo(opts, fn repo ->
        {pending, applied_without_file} = disagreements(repo, migrations_directory(opts))
        {pending, applied_without_file, unapplied_shared_migrations(repo)}
      end)

    if pending == [] and applied_without_file == [] and shared == [], do: IO.puts("none")
    if pending != [], do: IO.puts("pending: #{Enum.join(pending, " ")}")

    if applied_without_file != [],
      do: IO.puts("applied-without-file: #{Enum.join(applied_without_file, " ")}")

    if shared != [], do: IO.puts("shared-pending: #{Enum.join(shared, ", ")}")
  end

  defp disagreements(repo, path) do
    prefix = repo.default_prefix()

    unless table_exists?(repo, prefix, migration_source(repo)),
      do: raise(@missing_migration_table_error)

    migrations =
      Ecto.Migrator.migrations(repo, [path],
        prefix: prefix,
        skip_table_creation: true,
        migration_lock: false
      )

    carried = carried_versions(path)

    {for({:down, version, _name} <- migrations, do: version),
     for({:up, version, _name} <- migrations, version not in carried, do: version)}
  end

  # Ecto names an applied version with no file after a placeholder marker. The
  # set of versions the release actually carries answers the same question
  # without depending on that marker's text.
  defp carried_versions(path) do
    for file <- Path.wildcard(Path.join(path, "*.exs")),
        {version, "_" <> _name} <- [file |> Path.basename() |> Integer.parse()],
        into: MapSet.new(),
        do: version
  end

  # The shared code this release carries reads tables and columns from every
  # migration its pinned library ships, so each must already be in that schema's
  # own ledger. Every missing version is named at once.
  defp require_shared_migrations!(repo) do
    case unapplied_shared_migrations(repo) do
      [] ->
        :ok

      unapplied ->
        raise "These separately approved shared migrations must be applied before deployment: " <>
                Enum.join(unapplied, ", ")
    end
  end

  defp unapplied_shared_migrations(repo) do
    for {app, schema, _migrator} <- carried_shared(),
        version <-
          unapplied_versions(repo, schema, Application.app_dir(app, "priv/repo/migrations")),
        do: "#{schema} #{version}"
  end

  # A read only: with its table creation skipped and no migration lock the
  # migrator just selects the schema's ledger. A library whose ledger does not
  # exist yet has had none of its changes applied.
  defp unapplied_versions(repo, schema, path) do
    if table_exists?(repo, schema, "schema_migrations") do
      for {:down, version, _name} <-
            Ecto.Migrator.migrations(repo, [path],
              prefix: schema,
              skip_table_creation: true,
              migration_lock: false
            ),
          do: version
    else
      Enum.sort(carried_versions(path))
    end
  end

  defp apply_shared(repo), do: Enum.each(carried_shared(), fn {_, _, m} -> m.up(repo) end)

  # A shared library this site does not carry has no tables it reads or changes.
  defp carried_shared do
    carried = Application.spec(@app, :applications)
    for {app, _schema, _migrator} = shared <- @shared, app in carried, do: shared
  end

  defp refuse_existing_state!(repo) do
    prefix = repo.default_prefix()
    source = migration_source(repo)

    if table_exists?(repo, prefix, source) do
      raise "#{prefix}.#{source} already exists: destroy and recreate the staging database"
    end

    if schema_exists?(repo, @platform_schema) do
      raise "#{@platform_schema} schema already exists: destroy and recreate the staging database"
    end
  end

  defp table_exists?(repo, prefix, table) do
    %{rows: [[exists?]]} = Ecto.Adapters.SQL.query!(repo, @table_exists, [prefix, table])
    exists?
  end

  defp schema_exists?(repo, schema) do
    %{rows: [[exists?]]} = Ecto.Adapters.SQL.query!(repo, @schema_exists, [schema])
    exists?
  end

  defp migration_source(repo), do: repo.config()[:migration_source] || "schema_migrations"

  # Loads the app and starts only its database connection, on the release
  # login unless `:config` names another, for as long as `fun` runs; returns
  # what `fun` returns.
  defp with_release_repo(opts, fun) do
    getenv = Keyword.get(opts, :getenv, &System.get_env/1)
    :ok = Application.ensure_loaded(@app)
    config = Keyword.get_lazy(opts, :config, fn -> migration_config!(getenv) end)
    Application.put_env(@app, Regents.Repo, config)
    {:ok, result, _started} = Ecto.Migrator.with_repo(Regents.Repo, fun)
    result
  end

  defp migrations_directory(opts),
    do: Keyword.get_lazy(opts, :migrations_path, &migrations_path/0)

  defp migrations_path, do: Application.app_dir(@app, "priv/repo/migrations")
end
