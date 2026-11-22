defmodule Regents.Keyfleet.Projects.Project do
  @moduledoc """
  One project inside a fleet: its name, which addresses use and which never
  changes, its title, which pages show, the Key that started it
  (`created_by_key`) and the Key that holds it now (`key`), both by number,
  and its state: `active`, `archived` or `deleted`.

  A Key holds at most one active project and five archived ones. It starts a
  project when it holds no active one (`start`), archives its active one
  (`archive`), and takes over any archived project when it holds no active
  one (`take_over`). Only the Key that started a project deletes it, once it
  is archived, whichever Key holds it then (`delete`): taking a project over
  lets a Key work in it, never delete it (Sean, 12 Nov 2026, 2a). The row
  stays, marked deleted, so its name and repository name are never used
  again, and everything else of it goes (`Regents.Keyfleet.Projects.Hold`).
  Projects stay with the Key's number when the Key changes hands. Only an
  active project takes new work.

  A project starts active, or archived for `general`, and its moves are
  declared in the `state_machine` block: an active project is archived
  (`archived`), a shared one deleted (`unshared`), and an archived project is
  taken over (`taken_over`) or deleted (`deleted`). A deleted project never
  moves again, and the database refuses an archived project that no Key holds.

  Its repository in the code store is named when the project starts: the
  fleet's own name for `general`, which keeps the fleet's first repository,
  and `<fleet id>-<name>` for every other. Fleet ids hold no hyphen, so no two
  projects of any fleets share a repository name; a job queued as the
  project starts makes it there (`Regents.Keyfleet.Code.Setup`). `hub_project_id` is its
  space in the fleet's notebook hub, once a job has made it
  (`Regents.Keyfleet.Notebooks.Space`).

  Every fleet has `general`, archived and held by Key 3 (Key 329 in Regents
  Club, `general_key/1`), which holds the starting goals, the fleet's first
  notebook space and its first repository (`bootstrap_general`). No Key ever
  deletes it (`Regents.Keyfleet.Projects.Validations.NotGeneral`).

  The Key holding a project chooses whether its page shows anyone its work
  (`show`, `shown_to_everyone`): its goals, its latest work, what it produced
  and the tasks nobody has joined yet or blocked, each by title. It starts shown to
  members only. The Key also gives it a one-line `description` (`describe`),
  which its page shows under the title and shares as its description.

  Every fleet also has shared projects, active and held by no Key
  (`shared`, `shared_names/1`): `understanding`, the fleet's notes on how its
  members work together, and, in every fleet but Regents Club, `scratchpad`,
  where each Key has a notebook of its own (`Regents.Keyfleet.Notebooks.Scratchpads`).
  No Key archives, takes over or deletes one, and none counts as a Key's
  active project. A shared project the fleet no longer shares is deleted
  (`unshared`, `Regents.Keyfleet.Projects.unshare!/1`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  alias Regents.Keyfleet.Graph.Checks.KeyActor
  alias Regents.Keyfleet.Graph.Validations.{FreshOwnership, KnownFleet}
  alias Regents.Keyfleet.Projects.Hold

  @bigint 9_223_372_036_854_775_807
  @states [:active, :archived, :deleted]
  # One line of text, never a control character.
  @description [max_length: 160, match: ~r/\A[^\x00-\x1f\x7f]*\z/]
  # The most archived projects one Key holds.
  @archived_most 5

  @doc "The most archived projects one Key holds."
  def archived_most, do: @archived_most

  @doc "The names of the projects the fleet shares, held by no Key: Regents Club has no scratchpad."
  def shared_names("regents_club"), do: ["understanding"]
  def shared_names(_fleet_id), do: ["scratchpad", "understanding"]

  @doc "The Key that holds a fleet's `general`: 329 in Regents Club, 3 in every other."
  def general_key("regents_club"), do: 329
  def general_key(_fleet_id), do: 3

  postgres do
    table "projects"
    schema("keyfleet_app")
    repo(Regents.Repo)

    identity_wheres_to_sql(one_active_per_key: "state = 'active'")

    check_constraints do
      check_constraint(:name, "projects_name_shape",
        check: "name ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(name) <= 32"
      )

      check_constraint(:state, "projects_state",
        check: "state IN ('active', 'archived', 'deleted')"
      )

      check_constraint(:state, "projects_archived_held",
        check: "key IS NOT NULL OR state <> 'archived'"
      )
    end
  end

  state_machine do
    initial_states([:active, :archived])

    transitions do
      transition(:archived, from: :active, to: :archived)
      transition(:taken_over, from: :archived, to: :active)
      transition(:deleted, from: :archived, to: :deleted)
      transition(:unshared, from: :active, to: :deleted)
    end
  end

  actions do
    # The read a guarded change of state reads its row back with.
    read :read do
      primary? true
      public? false
    end

    # The fleet's projects, oldest first, so `general` leads; a deleted one
    # is left out.
    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and state != :deleted)
      prepare build(sort: [inserted_at: :asc, name: :asc])
    end

    # Anyone reads a fleet's projects as their pages show them, oldest first:
    # each one's title and line, the Key holding it, whether it is archived
    # and whether its page shows its work to everyone.
    read :titles do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and state != :deleted)

      prepare build(
                sort: [inserted_at: :asc, name: :asc],
                select: [:fleet_id, :name, :title, :description, :key, :state, :shown_to_everyone]
              )
    end

    # Anyone reads when the fleet's projects were started, newest first, from
    # just past `before_at` and `before_name`, `limit` at most: each one's
    # title and the Key that started it. A deleted one is left out. `keys`
    # keeps those the Keys started (`Regents.Keyfleet.Preparations.DoneBy`); a
    # project names no wallet.
    read :started_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_at, :utc_datetime_usec, allow_nil?: false
      argument :before_name, :string, constraints: [trim?: false]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 200]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id) and state != :deleted)

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [inserted_at: :desc, name: :asc], before: [:before_at, :before_name]}

      prepare {Regents.Keyfleet.Preparations.DoneBy, key: :created_by_key}
      prepare build(select: [:fleet_id, :name, :title, :created_by_key, :inserted_at])
    end

    read :named do
      argument :fleet_id, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id) and name == ^arg(:name) and state != :deleted)
      get? true
    end

    # The fleet's project by name in any state, deleted included, for the
    # names that are never used again.
    read :ever_named do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id) and name == ^arg(:name))
      get? true
    end

    # The projects one Key holds in one state, oldest first.
    read :held do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :key, :integer, allow_nil?: false
      argument :state, :atom, allow_nil?: false, constraints: [one_of: @states]
      filter expr(fleet_id == ^arg(:fleet_id) and key == ^arg(:key) and state == ^arg(:state))
      prepare build(sort: [inserted_at: :asc, name: :asc])
    end

    # The project whose repository git asks for by name.
    read :by_repository do
      argument :repository, :string, allow_nil?: false, constraints: [trim?: false]
      filter expr(repository == ^arg(:repository) and state != :deleted)
      get? true
    end

    # The project of a repository in any state, its row held until the
    # transaction ends: a delete of it either committed already or waits
    # (`Regents.Keyfleet.Code.Setup`).
    read :locked_by_repository do
      public? false
      argument :repository, :string, allow_nil?: false, constraints: [trim?: false]
      filter expr(repository == ^arg(:repository))
      get? true
      prepare fn query, _context -> Ash.Query.lock(query, :for_update) end
    end

    # The fleet's project of that name in any state, its row held until the
    # transaction ends: a delete of it either committed already or waits
    # (`Regents.Keyfleet.Atlas.ReadHub`).
    read :locked_named do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id) and name == ^arg(:name))
      get? true
      prepare fn query, _context -> Ash.Query.lock(query, :for_update) end
    end

    # The four Key steps call `Hold` from a function, so a change to it
    # recompiles nothing here.

    # A project's page as anyone reads it: the project, whether its page shows
    # its work to everyone, and nothing else.
    read :page do
      argument :fleet_id, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id) and name == ^arg(:name) and state != :deleted)

      prepare build(
                select: [:fleet_id, :name, :title, :description, :key, :state, :shown_to_everyone]
              )

      get? true
    end

    # A member starts a project as one of the fleet's Keys, which holds it.
    action :start, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      argument :title, :string, allow_nil?: false
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Hold.run(input, [step: :start], context) end
    end

    # The Key's active project becomes archived, still the Key's.
    action :archive, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Hold.run(input, [step: :archive], context) end
    end

    # An archived project, any Key's, becomes the acting Key's active one.
    action :take_over, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Hold.run(input, [step: :take_over], context) end
    end

    # An archived project the acting Key started, never `general`, is
    # deleted for good, whichever Key holds it.
    action :delete, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      validate KnownFleet
      validate Regents.Keyfleet.Projects.Validations.NotGeneral, only_when_valid?: true
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Hold.run(input, [step: :delete], context) end
    end

    # The Key holding a project shows its work to everyone on its page, or to
    # members only again.
    action :show, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      argument :shown_to_everyone, :boolean, allow_nil?: false
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Hold.run(input, [step: :show], context) end
    end

    # The Key holding a project gives it a line its page shows under the
    # title and shares as its description, or clears it with none.
    action :describe, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :name, :string, allow_nil?: false, constraints: [trim?: false]
      argument :description, :string, constraints: @description
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Hold.run(input, [step: :describe], context) end
    end

    create :create do
      public? false
      accept [:fleet_id, :name, :title, :key]
      validate KnownFleet
      change set_attribute(:state, :active)

      change fn changeset, _context ->
        %{fleet_id: fleet_id, name: name, key: key} = changeset.attributes

        Ash.Changeset.force_change_attributes(changeset,
          created_by_key: key,
          repository: "#{fleet_id}-#{name}"
        )
      end

      change Regents.Keyfleet.Notebooks.Changes.MakeSpace
      change Regents.Keyfleet.Code.Changes.MakeRepository
    end

    # Gives a fleet its `general` once; a fleet that has it keeps it as it is.
    create :general do
      public? false
      accept [:fleet_id]
      upsert? true
      upsert_fields [:title]

      change fn changeset, _context ->
        Ash.Changeset.force_change_attributes(changeset,
          name: "general",
          title: "General",
          key: general_key(Ash.Changeset.get_attribute(changeset, :fleet_id)),
          state: :archived,
          repository: Ash.Changeset.get_attribute(changeset, :fleet_id)
        )
      end
    end

    # Gives a fleet its shared project `name` once, active and held by no
    # Key; a fleet that has it keeps it, its title made canonical again.
    create :shared do
      public? false
      accept [:fleet_id, :name, :title]
      upsert? true
      upsert_fields [:title]
      change set_attribute(:state, :active)

      change fn changeset, _context ->
        %{fleet_id: fleet_id, name: name} = changeset.attributes
        Ash.Changeset.force_change_attribute(changeset, :repository, "#{fleet_id}-#{name}")
      end
    end

    # Deletes a shared project the fleet no longer shares, as a deleted
    # project goes (`Regents.Keyfleet.Projects.Changes.Forget`).
    update :unshared do
      public? false
      accept []
      require_atomic? false
      change filter(expr(state == :active and is_nil(key)))
      change transition_state(:deleted)
      change Regents.Keyfleet.Projects.Changes.Forget
      change Regents.Keyfleet.Notebooks.Changes.ForgetScratchpads
    end

    update :archived do
      public? false
      accept []
      change filter(expr(state == :active))
      change transition_state(:archived)
    end

    update :taken_over do
      public? false
      accept []
      argument :key, :integer, allow_nil?: false
      change filter(expr(state == :archived))
      change set_attribute(:key, arg(:key))
      change transition_state(:active)
    end

    update :deleted do
      public? false
      accept []
      argument :key, :integer, allow_nil?: false
      require_atomic? false
      change filter(expr(state == :archived and created_by_key == ^arg(:key)))
      change transition_state(:deleted)
      change Regents.Keyfleet.Projects.Changes.Forget
    end

    update :shown do
      public? false
      accept [:shown_to_everyone]
      argument :key, :integer, allow_nil?: false
      change filter(expr(state != :deleted and key == ^arg(:key)))
    end

    update :described do
      public? false
      accept [:description]
      argument :key, :integer, allow_nil?: false
      change filter(expr(state != :deleted and key == ^arg(:key)))
    end

    # A project deleted while its space was being made records none; its
    # delete run looks for that space by its tag (`Regents.Keyfleet.Notebooks.DeleteSpace`).
    update :record_space do
      accept [:hub_project_id]
      require_atomic? false
      change filter(expr(state != :deleted))
      change Regents.Keyfleet.Notebooks.Changes.QueueRoster
    end
  end

  policies do
    policy action([:start, :archive, :take_over, :delete, :show, :describe]) do
      authorize_if KeyActor
    end

    policy action([:titles, :page, :started_before]) do
      authorize_if always()
    end

    policy action([:in_fleet, :named]) do
      authorize_if actor_attribute_equals(:role, :system)
      authorize_if Regents.Keyfleet.Graph.Checks.KeyReader
    end

    policy action([
             :read,
             :create,
             :general,
             :shared,
             :ever_named,
             :held,
             :archived,
             :taken_over,
             :deleted,
             :unshared,
             :shown,
             :described,
             :record_space,
             :by_repository,
             :locked_by_repository,
             :locked_named
           ]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true

    attribute :name, :string,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/, max_length: 32, trim?: false]

    attribute :title, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 60, match: ~r/\A[^\x00-\x1f\x7f]*\z/]

    # The Key that started it, the only Key that deletes it; none for the
    # projects every fleet starts with.
    attribute :created_by_key, :integer, public?: true
    # The Key that holds it; none for a shared project, which the whole fleet holds.
    attribute :key, :integer, public?: true, constraints: [min: 0]
    attribute :state, :atom, allow_nil?: false, public?: true, constraints: [one_of: @states]
    attribute :repository, :string, allow_nil?: false, public?: true
    attribute :hub_project_id, :string, public?: true
    # Whether the project's page shows its work to everyone, or to members only.
    attribute :shown_to_everyone, :boolean, allow_nil?: false, default: false, public?: true
    # One line its page shows under the title and shares as its description.
    attribute :description, :string, public?: true, constraints: @description
    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :one_repository, [:repository]

    identity :one_active_per_key, [:fleet_id, :key],
      where: expr(state == :active),
      message: "This Key is already working on a project."
  end
end
