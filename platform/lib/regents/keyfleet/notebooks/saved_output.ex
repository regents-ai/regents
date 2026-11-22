defmodule Regents.Keyfleet.Notebooks.SavedOutput do
  @moduledoc """
  Keyfleet's own copy of one saved notebook page, kept under its address
  (`Regents.Keyfleet.Notebooks.result_url/4`): the fleet, the notebook, the version
  or background run that made the page, and when the hub made it, in
  milliseconds since 1970. `succeeded` is whether the page is a background
  run's that succeeded, as the hub named the run when it answered the page
  (`Regents.Keyfleet.Notebooks.run_succeeded?/1`), so a notebook's last good page is
  read from the copies alone (`:last_succeeded`). `failure` is how a run
  that didn't succeed stopped, `stage` and `message` as the hub records them,
  once the run's record has been read (`Regents.Keyfleet.Notebooks.record_run_failure/3`),
  so a notebook's newest run page says how it went whoever reads it
  (`:newest_runs`); nil for any other copy.

  So a copy is plain, succeeded or failed, and never succeeded with a failure
  recorded: the database refuses that row, `:mark_succeeded` leaves a copy
  with a failure as it is, and `:record_failure` one marked succeeded or with
  a failure already.

  A hub keeps only a notebook's newest versions and recent runs, replaces a
  version's page when the same code runs again, and drops everything when a
  notebook is deleted. The copy is taken before the address is handed out
  (`RegentsWeb.Keyfleet.Plugs.NotebookGateway`), so an address that was handed out
  shows what it showed while the copy is kept. The first copy under an
  address stays until one of the fleet's members removes it or, for a
  background run's page, until it is cleared once its time is past
  (`:past_keeping`, `Regents.Keyfleet.Notebooks.RunPagePruner`); the address is then
  gone.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Notebooks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notebook_saved_outputs"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:failure, "notebook_saved_outputs_succeeded_or_failed",
        check: "NOT succeeded OR failure IS NULL"
      )
    end
  end

  actions do
    create :keep do
      accept [:fleet_id, :notebook_id, :source_id, :saved_at, :page, :succeeded]
      upsert? true
      upsert_identity :unique_address
      upsert_fields []
    end

    destroy :remove

    # Every copy, page and all. A filter that asks about other copies
    # (`:past_keeping`) is authorised through it.
    read :read do
      primary? true
    end

    # A copy kept before copies recorded their run's outcome, of a run the
    # hub names succeeded (`Regents.Keyfleet.Notebooks.MarkSucceeded`), unless it
    # records how its run failed.
    update :mark_succeeded do
      accept []
      change filter(expr(is_nil(failure)))
      change set_attribute(:succeeded, true)
    end

    # How the run failed, on a copy that records none yet and is not marked
    # succeeded: one recorded stays.
    update :record_failure do
      accept [:failure]
      change filter(expr(is_nil(failure) and not succeeded))
    end

    read :at do
      get? true
      argument :fleet_id, :string, allow_nil?: false
      argument :notebook_id, :string, allow_nil?: false
      argument :source_id, :string, allow_nil?: false
      argument :saved_at, :integer, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and notebook_id == ^arg(:notebook_id) and
                 source_id == ^arg(:source_id) and saved_at == ^arg(:saved_at)
             )
    end

    # Where the fleet's copies made by any of `source_ids` are kept, without
    # their pages.
    read :of_sources do
      argument :fleet_id, :string, allow_nil?: false
      argument :source_ids, {:array, :string}, allow_nil?: false

      filter expr(fleet_id == ^arg(:fleet_id) and source_id in ^arg(:source_ids))
      prepare build(select: [:notebook_id, :source_id, :saved_at])
    end

    # The newest copy of each of `notebook_ids`' pages from a run that
    # succeeded, without its page.
    read :last_succeeded do
      argument :fleet_id, :string, allow_nil?: false
      argument :notebook_ids, {:array, :string}, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and notebook_id in ^arg(:notebook_ids) and succeeded
             )

      prepare build(
                select: [:notebook_id, :source_id, :saved_at],
                distinct: [:notebook_id],
                distinct_sort: [saved_at: :desc]
              )
    end

    # The newest copy of each of `notebook_ids`' pages from a background run,
    # whoever started it, without its page.
    read :newest_runs do
      argument :fleet_id, :string, allow_nil?: false
      argument :notebook_ids, {:array, :string}, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and notebook_id in ^arg(:notebook_ids) and
                 string_starts_with(source_id, "run_")
             )

      prepare build(
                select: [:notebook_id, :source_id, :saved_at, :succeeded, :failure],
                distinct: [:notebook_id],
                distinct_sort: [saved_at: :desc]
              )
    end

    # The fleet's copies of background runs' pages not marked succeeded,
    # without their pages.
    read :unmarked_runs do
      argument :fleet_id, :string, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and not succeeded and
                 string_starts_with(source_id, "run_")
             )

      prepare build(select: [:notebook_id, :source_id])
    end

    # The copies of background runs' pages the hub made before `before`, in
    # milliseconds since 1970, that may be cleared: each has a newer run page
    # of its notebook, so it is not the one `:newest_runs` answers; it did
    # not succeed, or has a newer page of its notebook that did, so it is not
    # the one `:last_succeeded` answers; and no Key has it public.
    read :past_keeping do
      argument :before, :integer, allow_nil?: false

      filter expr(
               string_starts_with(source_id, "run_") and saved_at < ^arg(:before) and
                 exists(
                   Regents.Keyfleet.Notebooks.SavedOutput,
                   fleet_id == parent(fleet_id) and notebook_id == parent(notebook_id) and
                     string_starts_with(source_id, "run_") and saved_at > parent(saved_at)
                 ) and
                 (not succeeded or
                    exists(
                      Regents.Keyfleet.Notebooks.SavedOutput,
                      fleet_id == parent(fleet_id) and notebook_id == parent(notebook_id) and
                        succeeded and saved_at > parent(saved_at)
                    )) and
                 not exists(publications, true)
             )
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  identities do
    identity :unique_address, [:fleet_id, :notebook_id, :source_id, :saved_at]
  end

  attributes do
    uuid_primary_key :id
    attribute :fleet_id, :string, allow_nil?: false
    attribute :notebook_id, :string, allow_nil?: false
    attribute :source_id, :string, allow_nil?: false
    attribute :saved_at, :integer, allow_nil?: false, constraints: [min: 1]
    attribute :page, :binary, allow_nil?: false
    attribute :succeeded, :boolean, allow_nil?: false, default: false

    attribute :failure, :map do
      constraints fields: [
                    stage: [type: :string, allow_nil?: false],
                    message: [type: :string, allow_nil?: false]
                  ]
    end

    create_timestamp :inserted_at
  end

  relationships do
    # The Keys' publications of this page, by its address
    # (`Regents.Keyfleet.Notebooks.result_path/3`).
    has_many :publications, Regents.Keyfleet.Projects.Publication do
      no_attributes? true

      filter expr(
               fleet_id == parent(fleet_id) and
                 page ==
                   parent(
                     "/results/" <>
                       notebook_id <>
                       "/" <>
                       source_id <>
                       "/" <>
                       type(saved_at, :string)
                   )
             )
    end
  end
end
