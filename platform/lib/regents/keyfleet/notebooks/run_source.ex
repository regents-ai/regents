defmodule Regents.Keyfleet.Notebooks.RunSource do
  @moduledoc """
  What a background run started through this site ran from, recorded when it
  started (`Regents.Keyfleet.Notebooks.Runs.start/5`): the sha256 of the notebook's
  saved code as Keyfleet read it just before asking for the run, and every
  file of the notebook then with its revision
  (`Regents.Keyfleet.Notebooks.Files.manifest/4`), so a result read later says which
  code and files made it and whether the notebook has changed since. A run
  started on the notebook host itself has none.

  The first record of a run stays: starting it again with the same
  idempotency key answers the same run, which ran from the same code.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Notebooks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notebook_run_sources"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:code_sha256, "notebook_run_sources_code_sha256",
        check: "code_sha256 ~ '^[0-9a-f]{64}$'"
      )
    end
  end

  actions do
    create :record do
      accept [:fleet_id, :run_id, :notebook_id, :code_sha256, :files, :files_complete]
      upsert? true
      upsert_fields []
      return_skipped_upsert? true
    end

    read :of_run do
      get? true
      argument :fleet_id, :string, allow_nil?: false
      argument :run_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and run_id == ^arg(:run_id))
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false
    attribute :run_id, :string, primary_key?: true, allow_nil?: false
    attribute :notebook_id, :string, allow_nil?: false
    attribute :code_sha256, :string, allow_nil?: false

    # Each file of the notebook at any depth, `{path, size, revision}`, and
    # whether those were all of them: completeness, not freshness.
    attribute :files, {:array, :map}, allow_nil?: false, default: []
    attribute :files_complete, :boolean, allow_nil?: false

    create_timestamp :started_at
  end
end
