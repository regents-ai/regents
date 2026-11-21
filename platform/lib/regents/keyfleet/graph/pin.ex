defmodule Regents.Keyfleet.Graph.Pin do
  @moduledoc """
  Something a fleet's members keep at hand in one project of their
  workspace: a notebook in its Docs (`place: :docs`, `target` the notebook's
  id) or a file or folder of its code in its Code (`place: :code`, `target`
  the path from the top of the project's repository). Every member sees the
  same pins, and any member pins; a pin is its pinner's, so only they unpin
  it. An agent paired with a person pins and unpins as that person, so a
  person's pins and their agents' are one set. A Key whose edits a vote of
  the fleet has restricted neither pins nor unpins, as it adds nothing else
  to the workspace. A project's pins go with it when it is deleted.

  The title is what the page showed when it was pinned, so a pin still reads
  sensibly after the notebook or file it names is gone. Pinning what is
  already pinned keeps the one pin: the pinner's press takes the newer title,
  and anyone else's leaves the pin as its pinner made it.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Graph,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # How many pins a place shows, newest first.
  @shown 100

  postgres do
    table "workspace_pins"
    schema("keyfleet_app")
    repo(Regents.Repo)
  end

  actions do
    destroy :destroy do
      primary? true
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      validate Regents.Keyfleet.Graph.Validations.Unrestricted, before_action?: true
    end

    create :pin do
      accept [:fleet_id, :project, :place, :target, :title, :folder?]
      change set_attribute(:human_account_id, actor(:human_account_id))
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      upsert? true
      upsert_identity :one_per_target
      upsert_fields [:title]
      upsert_condition expr(human_account_id == ^actor(:human_account_id))
      return_skipped_upsert? true
      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      validate Regents.Keyfleet.Projects.Validations.Active, only_when_valid?: true
      validate Regents.Keyfleet.Graph.Validations.Unrestricted, before_action?: true
    end

    # The pins in one place, the whole fleet's or one project's, newest first.
    read :in_place do
      argument :fleet_id, :string, allow_nil?: false
      argument :place, :atom, allow_nil?: false, constraints: [one_of: [:docs, :code]]
      argument :project, :string

      filter expr(
               fleet_id == ^arg(:fleet_id) and place == ^arg(:place) and
                 (is_nil(^arg(:project)) or project == ^arg(:project))
             )

      prepare build(sort: [inserted_at: :desc], limit: @shown)
    end

    # Every pin of one project, for its deletion.
    read :of_project do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and project == ^arg(:project))
    end

    destroy :forget do
      public? false
    end
  end

  policies do
    policy action(:in_place) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :workspace, scope: :fleet_id}
    end

    # A person, or an agent paired with a person here, who pins as its person.
    policy action([:pin, :destroy]) do
      forbid_unless Regents.Keyfleet.Keys.Checks.ActsForPerson
      authorize_if {Regents.Keyfleet.Access.Check, write: :workspace, scope: :fleet_id}
    end

    policy action(:destroy) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    policy action([:of_project, :forget]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :project, :string, allow_nil?: false, public?: true

    attribute :place, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:docs, :code]]

    attribute :target, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 1024, trim?: false]

    attribute :title, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 1024, trim?: false]

    attribute :folder?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :human_account_id, :integer, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_target, [:fleet_id, :project, :place, :target]
  end
end
