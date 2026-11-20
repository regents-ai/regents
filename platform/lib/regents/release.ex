defmodule Regents.Release do
  @moduledoc false
  use Boundary, top_level?: true, deps: [Regents, RegentsWeb, Regents.LocalDatabaseFixture]

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
  # changes apply.
  @shared [
    {:regent_identity, "regent_identity", RegentIdentity.Migrator},
    {:regent_agents, "regent_agents", RegentAgents.Migrator},
    {:regent_points, "regent_points", RegentPoints.Migrator},
    {:regent_payments, "regent_payments", RegentPayments.Migrator}
  ]

  # Every product folded into this site, with the schema its tables live in. Each
  # keeps its own migrations (`priv/<product>/migrations`) and its own ledger
  # (`<schema>.schema_migrations`) beside this site's own, all on `Regents.Repo`.
  @products [{"techtree", "techtree_app"}]

  @doc false
  # `mix ash.codegen` (`Mix.Tasks.Regents.Codegen`) writes each product's
  # migrations into its own folder.
  def products, do: @products

  def migration_config!, do: Regents.DatabaseConfig.release_config!()

  def migrate do
    with_release_repo(fn repo ->
      require_signed_access_schema!(repo)
      migrate_areas!(repo)
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
  running it at once apply each change once.
  """
  def migrate_shared do
    applied =
      with_release_repo(fn repo ->
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
    RegentAgents.Migrator.require_pairing_history!(repo)
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

  # `put-paper` calls this inside the running site, so the save uses the site's own
  # database connections and clears what the page keeps in one step.
  defp save_paper(attributes) do
    paper = Regents.PaperProDaily.put_paper!(attributes, actor: %Regents.Account.Actors.System{})
    RegentsWeb.PaperProDaily.Feed.delete_all!()

    IO.puts("Paper Pro Daily #{paper.date}: \"#{paper.title}\" saved.")
  end

  @doc "Saves post.md and its cover using /app/bin/put-post <folder>. The slug identifies the post."
  def put_post(folder) do
    attributes = Regents.Blog.PostFile.read!(folder)
    # Render before saving so a malformed body never replaces a readable post.
    RegentBlog.markdown(attributes.markdown)

    post =
      with_release_repo(fn _repo ->
        Regents.Blog.put_post!(attributes, actor: %Regents.Account.Actors.System{})
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
  migration into `regents_app` and each folded product's schema
  (`prepare_database!/1`).

  It refuses any database that already carries migration state or the
  regent_names schema, and it repairs nothing: recovery from a half-finished
  bootstrap is to destroy and recreate the staging database. It reads only the
  database the release configuration resolves.
  """
  def bootstrap_staging do
    # The role is read before anything opens a connection, so no configuration
    # mistake can point this command at a database outside staging.
    if System.get_env(@deployment_role_variable) != @staging_role do
      raise @bootstrap_role_error
    end

    with_release_repo(fn repo ->
      refuse_existing_state!(repo)
      prepare_database!(repo)
    end)
  end

  @doc false
  # Staging's first deployment and every local database
  # (`Regents.LocalDatabaseFixture`) are prepared the same way, in production's
  # order: the tables this repository reads but does not own (the fixture is the
  # only definition of their shape), every shared change this release carries,
  # then this site's own migrations and each folded product's.
  def prepare_database!(repo) do
    Regents.LocalDatabaseFixture.create_shared_tables!()
    apply_shared(repo)
    migrate_areas!(repo)
  end

  @doc """
  Lists what a deployed database and the release disagree about.

  Prints every migration the release carries that the database has not applied,
  in this site's own schema and each folded product's, under `pending:`; every
  version the database has applied whose file the release does not carry under
  `applied-without-file:`; and every shared change `migrate_shared/0` would apply
  under `shared-pending:`. Each is listed as schema and version; a deployment is
  refused while a shared change is listed. Prints `none` when all three are
  empty. It applies nothing, creates nothing, and takes no migration lock.
  """
  def pending_migrations do
    lists =
      with_release_repo(fn repo ->
        unless table_exists?(repo, repo.default_prefix(), migration_source(repo)),
          do: raise(@missing_migration_table_error)

        areas =
          for {schema, path} <- areas(repo), do: {schema, disagreements(repo, schema, path)}

        [
          {"pending", for({schema, {pending, _}} <- areas, v <- pending, do: "#{schema} #{v}")},
          {"applied-without-file",
           for({schema, {_, without}} <- areas, v <- without, do: "#{schema} #{v}")},
          {"shared-pending", unapplied_shared_migrations(repo)}
        ]
      end)

    case Enum.reject(lists, &match?({_label, []}, &1)) do
      [] ->
        IO.puts("none")

      lists ->
        Enum.each(lists, fn {label, list} -> IO.puts("#{label}: #{Enum.join(list, ", ")}") end)
    end
  end

  # The versions in `path` the schema's ledger lacks, and the versions it holds
  # with no file in `path`. A read only: with its table creation skipped and no
  # migration lock the migrator just selects the ledger. A schema whose ledger
  # does not exist yet has had none of its changes applied.
  defp disagreements(repo, schema, path) do
    if table_exists?(repo, schema, migration_source(repo)) do
      migrations =
        Ecto.Migrator.migrations(repo, [path],
          prefix: schema,
          skip_table_creation: true,
          migration_lock: false
        )

      carried = carried_versions(path)

      {for({:down, version, _name} <- migrations, do: version),
       for({:up, version, _name} <- migrations, version not in carried, do: version)}
    else
      {Enum.sort(carried_versions(path)), []}
    end
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
        {pending, _without} =
          disagreements(repo, schema, Application.app_dir(app, "priv/repo/migrations")),
        version <- pending,
        do: "#{schema} #{version}"
  end

  defp apply_shared(repo), do: Enum.each(carried_shared(), fn {_, _, m} -> m.up(repo) end)

  # A shared library this site does not carry has no tables it reads or changes.
  defp carried_shared do
    carried = Application.spec(@app, :applications)
    for {app, _schema, _migrator} = shared <- @shared, app in carried, do: shared
  end

  defp refuse_existing_state!(repo) do
    source = migration_source(repo)

    for {schema, _path} <- areas(repo), table_exists?(repo, schema, source) do
      raise "#{schema}.#{source} already exists: destroy and recreate the staging database"
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
  # login, for as long as `fun` runs; returns what `fun` returns.
  defp with_release_repo(fun) do
    :ok = Application.ensure_loaded(@app)
    Application.put_env(@app, Regents.Repo, migration_config!())
    {:ok, result, _started} = Ecto.Migrator.with_repo(Regents.Repo, fun)
    result
  end

  # This site's own schema and migrations first, then each folded product's.
  defp areas(repo) do
    [
      {repo.default_prefix(), Application.app_dir(@app, "priv/repo/migrations")}
      | for(
          {product, schema} <- @products,
          do: {schema, Application.app_dir(@app, "priv/#{product}/migrations")}
        )
    ]
  end

  defp migrate_areas!(repo),
    do: Enum.each(areas(repo), fn {schema, path} -> repo.migrate!(path, schema) end)
end
