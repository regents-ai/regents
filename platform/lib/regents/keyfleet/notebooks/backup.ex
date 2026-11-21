defmodule Regents.Keyfleet.Notebooks.Backup do
  @moduledoc """
  A daily copy of one notebook's code (`Regents.Keyfleet.Notebooks.Backups`), taken
  only when the notebook changed since its last copy (`changed_at`, when its
  hub last saved it), and kept for 90 days.

  Beside the code it keeps who could edit the notebook when it was copied:
  its creator in the hub (`author`), the Key whose scratchpad it was (`key`)
  and whether it was unlocked. Any of them brings the copy back as a new
  notebook of their own in the same project (`Regents.Keyfleet.Notebooks.restore/5`),
  whether or not the notebook is still there. A project deleted takes its
  copies with it (`Regents.Keyfleet.Projects.Changes.Forget`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Notebooks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notebook_backups"
    schema("keyfleet_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:fleet_id, :project, :changed_at])
      index([:inserted_at])
    end
  end

  actions do
    defaults [:read]

    create :keep do
      accept [
        :fleet_id,
        :project,
        :notebook_id,
        :title,
        :code,
        :author,
        :key,
        :unlocked,
        :changed_at
      ]

      upsert? true
      upsert_identity :one_per_change
      upsert_fields []
    end

    # When each of the fleet's notebooks last changed, as its newest copy says.
    read :newest do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id))

      prepare build(
                distinct: [:notebook_id],
                distinct_sort: [changed_at: :desc],
                select: [:notebook_id, :changed_at]
              )
    end

    read :of_project do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))
    end

    # The copies of a project's notebooks, newest first, without their code.
    read :copies do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))

      prepare build(
                sort: [changed_at: :desc],
                select: [:id, :notebook_id, :title, :author, :key, :unlocked, :changed_at]
              )
    end

    # The copies of every notebook of the fleet from just past `before_at` and
    # `before_id`, newest first, `limit` at most, without their code. `keys`
    # keeps the copies changed last as those Keys; a copy names no wallet, so
    # `wallet` alone keeps none (`Regents.Keyfleet.Preparations.DoneBy`).
    read :changed_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_at, :utc_datetime_usec, allow_nil?: false
      argument :before_id, :uuid
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 200]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id))

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [changed_at: :desc, id: :asc], before: [:before_at, :before_id]}

      prepare {Regents.Keyfleet.Preparations.DoneBy, key: :key}

      prepare build(select: [:id, :fleet_id, :project, :notebook_id, :title, :key, :changed_at])
    end

    read :older_than do
      argument :before, :utc_datetime_usec, allow_nil?: false
      filter expr(inserted_at < ^arg(:before))
    end

    destroy :forget
  end

  policies do
    # When the fleet's notebooks changed is read as its workspace is.
    policy action(:changed_before) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :workspace, scope: :fleet_id}
    end

    policy action([:read, :keep, :newest, :of_project, :copies, :older_than, :forget]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  identities do
    identity :one_per_change, [:fleet_id, :notebook_id, :changed_at]
  end

  attributes do
    uuid_primary_key :id
    attribute :fleet_id, :string, allow_nil?: false
    attribute :project, :string, allow_nil?: false
    attribute :notebook_id, :string, allow_nil?: false
    attribute :title, :string, allow_nil?: false
    attribute :code, :string, allow_nil?: false, constraints: [trim?: false, allow_empty?: true]
    attribute :author, :string, allow_nil?: false
    attribute :key, :integer, constraints: [min: 0]
    attribute :unlocked, :boolean, allow_nil?: false
    attribute :changed_at, :utc_datetime_usec, allow_nil?: false
    create_timestamp :inserted_at
  end
end
