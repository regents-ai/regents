defmodule Regents.Keyfleet.Projects.Publication do
  @moduledoc """
  Something a Key made public in one of its fleet's projects, for the
  workspace's Public place (`RegentsWeb.Keyfleet.WorkspacePage`), which anyone reads.

  A Key makes public only what it made, of four kinds. Posts: the posts a
  Key wrote in one of the fleet's rooms from one place in it to another
  (`room`, `from_seq`, `to_seq`), word for word, shown in the project it
  names. An item: one workspace item the Key added (`item`), as it stands,
  shown in its own project while it isn't archived; each item is public at
  most once. A page: one saved notebook page its person or agent made
  (`page`, the page's path on the fleet's notebook host), which then opens
  for anyone at its own address, from this site's own copy of it; each page
  is public at most once. A commit: the Key holding a project makes the
  project's code at one commit (`commit_hash`) public, read-only, files and
  folders; each commit once. Only what was written for the wallet that owns the Key when it
  makes it public shows, so a Key that changes hands never makes a former
  owner's work public. Making something public changes nothing where it
  lives, which keeps its readers; the Key takes it back by withdrawing the
  publication.

  Each step runs as the Key the same way a workspace write does
  (`Regents.Keyfleet.Graph.Checks.KeyActor`, `Regents.Keyfleet.Projects.Publish`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Keyfleet.Graph.Checks.KeyActor
  alias Regents.Keyfleet.Graph.Validations.{FreshOwnership, KnownFleet}
  alias Regents.Keyfleet.Projects.Publish

  @bigint 9_223_372_036_854_775_807

  # The most posts one publication spans.
  @most_posts 200

  @doc "The most posts one publication spans."
  def most_posts, do: @most_posts

  postgres do
    table "publications"
    schema("keyfleet_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:fleet_id, :project, :inserted_at])
    end

    check_constraints do
      check_constraint(:kind, "publications_kind",
        check: "kind IN ('posts', 'item', 'page', 'commit')"
      )

      check_constraint(:kind, "publications_shape",
        check: """
        (kind = 'posts' AND room IS NOT NULL AND from_seq IS NOT NULL AND to_seq IS NOT NULL AND item IS NULL AND page IS NULL AND commit_hash IS NULL)
        OR (kind = 'item' AND item IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL AND page IS NULL AND commit_hash IS NULL)
        OR (kind = 'page' AND page IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL AND item IS NULL AND commit_hash IS NULL)
        OR (kind = 'commit' AND commit_hash IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL AND item IS NULL AND page IS NULL)
        """
      )

      check_constraint(:to_seq, "publications_range",
        check: "from_seq >= 1 AND to_seq >= from_seq AND to_seq - from_seq < 200"
      )
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    # What the fleet's Keys made public, newest first: in one project, or in
    # every project for none, a page at a time when asked.
    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string
      pagination keyset?: true, required?: false, max_page_size: 100

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 (is_nil(^arg(:project)) or project == ^arg(:project))
             )

      prepare build(sort: [inserted_at: :desc, id: :asc])
    end

    create :record do
      public? false

      accept [
        :fleet_id,
        :project,
        :key,
        :author_wallet,
        :kind,
        :room,
        :from_seq,
        :to_seq,
        :item,
        :page,
        :commit_hash
      ]
    end

    # The publication of one item, if it is public.
    read :of_item do
      argument :fleet_id, :string, allow_nil?: false
      argument :item, :string, allow_nil?: false, constraints: [trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id) and item == ^arg(:item))
      get? true
    end

    destroy :remove do
      public? false
    end

    # A Key makes public the posts it wrote in one room, from one place in it
    # to another, in one of the fleet's active projects.
    action :publish_posts, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :project, :string, allow_nil?: false, constraints: [trim?: false]
      argument :room, :string, allow_nil?: false, constraints: [trim?: false]
      argument :from_seq, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :to_seq, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Publish.run(input, [step: :posts], context) end
    end

    # The publication of one saved notebook page, by its path, if it is public.
    read :of_page do
      argument :fleet_id, :string, allow_nil?: false
      argument :page, :string, allow_nil?: false, constraints: [trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id) and page == ^arg(:page))
      get? true
    end

    # The publication of one commit of a project's code, if it is public.
    read :of_commit do
      argument :fleet_id, :string, allow_nil?: false
      argument :project, :string, allow_nil?: false, constraints: [trim?: false]
      argument :commit_hash, :string, allow_nil?: false, constraints: [trim?: false]

      filter expr(
               fleet_id == ^arg(:fleet_id) and project == ^arg(:project) and
                 commit_hash == ^arg(:commit_hash)
             )

      get? true
    end

    # A Key makes public one workspace item it added, in the item's own
    # project, which is active.
    action :publish_item, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :item, :string, allow_nil?: false, constraints: [trim?: false]
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Publish.run(input, [step: :item], context) end
    end

    # A Key makes public one saved notebook page its person or agent made, by
    # the page's address, in the project whose notebook made it, which is
    # active.
    action :publish_page, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :page, :string, allow_nil?: false, constraints: [trim?: false]
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Publish.run(input, [step: :page], context) end
    end

    # The Key holding an active project makes its code at one commit public.
    action :publish_commit, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :project, :string, allow_nil?: false, constraints: [trim?: false]
      argument :commit_hash, :string, allow_nil?: false, constraints: [trim?: false]
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Publish.run(input, [step: :commit], context) end
    end

    # The Key that made something public takes it back.
    action :withdraw, :struct do
      constraints instance_of: __MODULE__
      argument :fleet_id, :string, allow_nil?: false
      argument :as_key, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :id, :uuid, allow_nil?: false
      validate KnownFleet
      validate FreshOwnership, only_when_valid?: true
      run fn input, context -> Publish.run(input, [step: :withdraw], context) end
    end
  end

  policies do
    policy action([:in_fleet, :of_item, :of_page, :of_commit]) do
      authorize_if always()
    end

    policy action([:publish_posts, :publish_item, :publish_page, :publish_commit, :withdraw]) do
      authorize_if KeyActor
    end

    policy action([:read, :record, :remove]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id, public?: true
    attribute :fleet_id, :string, allow_nil?: false, public?: true
    attribute :project, :string, allow_nil?: false, public?: true
    # The Key that made it public, and whose posts it shows.
    attribute :key, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    # The wallet that owned the Key when it was made public: only the posts
    # written for that wallet show, never a former owner's.
    attribute :author_wallet, :string, allow_nil?: false

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:posts, :item, :page, :commit]]

    attribute :room, :string, public?: true
    attribute :from_seq, :integer, public?: true, constraints: [min: 1]
    attribute :to_seq, :integer, public?: true, constraints: [min: 1]
    # The workspace item made public, by its id.
    attribute :item, :string, public?: true, constraints: [trim?: false]
    # The saved notebook page made public, by its path on the fleet's
    # notebook host (`Regents.Keyfleet.Notebooks.result_path/3`).
    attribute :page, :string, public?: true, constraints: [trim?: false]
    # The commit of the project's code made public, by its full hash.
    attribute :commit_hash, :string, public?: true, constraints: [trim?: false]
    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :one_per_item, [:fleet_id, :item]
    identity :one_per_page, [:fleet_id, :page]
    identity :one_per_commit, [:fleet_id, :project, :commit_hash]
  end
end
