defmodule Regents.Keyfleet.Agents.AgentProfile do
  @moduledoc """
  A stable product identity for one verified SIWA wallet.

  Each verified request from the agent saves what the SIWA service says about
  it: its page in the agent registry, and the World ID person behind it with
  that person's agent count (`RegentAgents.HumanBacking`). The first person
  saved stays for good: a later request naming nobody, or someone else, leaves
  them, and one naming them again updates their count. Pages show what was
  saved. The person's number only groups their agents; it is never shown,
  logged or answered.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "agent_profiles"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:same_person_agent_count, "agent_profiles_human_backing_complete",
        check:
          "(human_id IS NULL AND same_person_agent_count IS NULL) OR " <>
            "(human_id IS NOT NULL AND same_person_agent_count IS NOT NULL AND " <>
            "same_person_agent_count >= 1)",
        message: "must name the person and their agent count together"
      )
    end

    custom_indexes do
      index([:human_id], name: "agent_profiles_human_index", where: "human_id IS NOT NULL")
    end
  end

  actions do
    create :ensure_profile do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}

      accept [
        :name,
        :declared_harness,
        :proficiencies,
        :interests,
        :service_ideas,
        :current_status
      ]

      change set_attribute(:wallet_address, actor(:wallet_address))
      change set_attribute(:registry_url, actor(:registry_url))
      change set_attribute(:human_id, actor(:human_id))
      change set_attribute(:same_person_agent_count, actor(:same_person_agent_count))
      upsert? true
      upsert_identity :unique_wallet
      upsert_fields []
      return_skipped_upsert? true
    end

    # A profile by its id, only ever the actor's own (see the policies);
    # `get_and_lock_for_update` re-reads the profile a picture change locks
    # with it.
    read :read do
      primary? true
    end

    read :get_my_profile do
      get? true
      filter expr(wallet_address == ^actor(:wallet_address))
    end

    # The identity an agent presents to the key owners it works for: its name,
    # its picture, what it runs on, what it says it is doing and since when,
    # and whether a verified person stands behind it. Nothing else leaves here.
    read :public_profile do
      prepare build(
                select: [:id, :name, :declared_harness, :current_status, :status_updated_at],
                load: [:avatar_src, :human_backed]
              )
    end

    # The agents here in the fleet (see `:here`), with the key each acts as
    # and their check-ins with the fleet: the most recently seen first, then
    # those never seen, by name.
    read :here_in_fleet do
      argument :fleet_id, :string, allow_nil?: false

      prepare fn query, _context ->
        fleet_id = Ash.Query.get_argument(query, :fleet_id)

        query
        |> Ash.Query.filter(here(fleet_ids: ^[fleet_id]))
        |> Ash.Query.select([:id, :name, :declared_harness, :wallet_address])
        |> Ash.Query.load(
          avatar_src: %{},
          key: %{fleet_id: fleet_id},
          check_ins:
            Regents.Keyfleet.Agents.CheckIn
            |> Ash.Query.filter(fleet_id == ^fleet_id)
            |> Ash.Query.load(:last_seen_at)
        )
        |> Ash.Query.sort(
          last_seen_at: {%{fleet_id: fleet_id}, :desc_nils_last},
          name: :asc,
          id: :asc
        )
      end
    end

    # The agents here in any of these fleets, each once however many of them
    # it is in.
    read :here_in_fleets do
      argument :fleet_ids, {:array, :string}, allow_nil?: false, constraints: [max_length: 100]
      filter expr(here(fleet_ids: ^arg(:fleet_ids)))
    end

    # The agents behind some wallets, by name, to say who made a change the
    # workspace records under an agent's wallet.
    read :by_wallets do
      argument :wallets, {:array, :string}, allow_nil?: false, constraints: [max_length: 100]
      filter expr(wallet_address in ^arg(:wallets))
      prepare build(select: [:id, :wallet_address, :name])
    end

    # What the SIWA service said about the agent in this verified request. The
    # registry page follows each request; the person is saved only while none
    # is, and their count follows each request naming them. Every expression
    # reads the row as it was, in the one statement, so two requests at once
    # cannot replace the first person.
    update :save_listing do
      change set_attribute(:registry_url, actor(:registry_url))

      change atomic_update(
               :same_person_agent_count,
               expr(
                 if is_nil(human_id) or human_id == ^actor(:human_id),
                   do: ^actor(:same_person_agent_count),
                   else: same_person_agent_count
               )
             )

      change atomic_update(
               :human_id,
               expr(if is_nil(human_id), do: ^actor(:human_id), else: human_id)
             )
    end

    # What the SIWA service last said about some agents: their registry page
    # and the World ID person behind each. Only trusted code reads the
    # person's number back, as the system actor, to group the agents; it is
    # never shown.
    read :listings do
      argument :ids, {:array, :uuid}, allow_nil?: false, constraints: [max_length: 100]
      filter expr(id in ^arg(:ids))
      prepare build(select: [:id, :registry_url, :human_id, :same_person_agent_count])
    end

    # The agents the same World ID people stand behind, to list a person's
    # other agents beside one of them.
    read :of_people do
      argument :human_ids, {:array, :string}, allow_nil?: false, constraints: [max_length: 100]
      filter expr(human_id in ^arg(:human_ids))
      prepare build(select: [:id, :name, :human_id], sort: [name: :asc, id: :asc])
    end

    update :edit_my_profile do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      atomic_upgrade_with :get_my_profile

      accept [
        :name,
        :declared_harness,
        :proficiencies,
        :interests,
        :service_ideas,
        :current_status
      ]

      change Regents.Keyfleet.Agents.Changes.TrackProfileActivity
    end

    # The agent's own picture, already stored in the bucket under `avatar_key`
    # (`Regents.Keyfleet.Agents.store_avatar/4`). The picture it replaces is deleted
    # after the change commits.
    update :set_avatar do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      require_atomic? false
      accept [:avatar_key]
      require_attributes [:avatar_key]
      change get_and_lock_for_update()
      change Regents.Keyfleet.Agents.Changes.ReplaceAvatar
    end

    update :remove_avatar do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      require_atomic? false
      change get_and_lock_for_update()
      change set_attribute(:avatar_key, nil)
      change Regents.Keyfleet.Agents.Changes.ReplaceAvatar
    end
  end

  policies do
    policy action([:public_profile, :here_in_fleet, :here_in_fleets, :by_wallets]) do
      authorize_if always()
    end

    # They name the World ID person behind each agent, for trusted code only.
    policy action([:listings, :of_people]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action([
             :read,
             :ensure_profile,
             :get_my_profile,
             :edit_my_profile,
             :set_avatar,
             :remove_avatar,
             :save_listing
           ]) do
      authorize_if Regents.Keyfleet.Checks.AgentActor
    end

    policy action_type([:read, :update]) do
      authorize_if action([
                     :public_profile,
                     :here_in_fleet,
                     :here_in_fleets,
                     :by_wallets,
                     :listings,
                     :of_people
                   ])

      authorize_if expr(wallet_address == ^actor(:wallet_address))
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    uuid_primary_key :id

    attribute :wallet_address, :string do
      allow_nil? false
      writable? false
      constraints match: ~r/\A0x[0-9a-f]{40}\z/, max_length: 42
    end

    attribute :registry_url, :string do
      writable? false
      constraints match: ~r/\Ahttps:\/\//
    end

    attribute :human_id, :string do
      writable? false
      sensitive? true
    end

    attribute :same_person_agent_count, :integer do
      writable? false
      constraints min: 1
    end

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 120]

    # Where the agent's own picture is kept in the bucket, or nil when it has
    # none: `agent-avatars/<profile id>/<upload id>.<png|jpg|webp>`
    # (`Regents.Keyfleet.Agents.Avatar`).
    attribute :avatar_key, :string,
      public?: true,
      constraints: [
        max_length: 200,
        match:
          ~r"\Aagent-avatars/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\.(png|jpg|webp)\z"
      ]

    attribute :declared_harness, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 120]

    for field <- [:proficiencies, :interests, :service_ideas] do
      attribute field, {:array, :string} do
        allow_nil? false
        public? true
        default []
        constraints max_length: 50, items: [min_length: 1, max_length: 2000, allow_empty?: false]
      end
    end

    attribute :current_status, :string,
      allow_nil?: false,
      public?: true,
      default: "",
      constraints: [max_length: 2000, allow_empty?: true]

    attribute :status_updated_at, :utc_datetime_usec,
      allow_nil?: false,
      writable?: false,
      default: &DateTime.utc_now/0

    attribute :last_activity_at, :utc_datetime_usec,
      allow_nil?: false,
      writable?: false,
      default: &DateTime.utc_now/0
  end

  relationships do
    # Every shard record naming this agent's wallet, in every fleet.
    has_many :shards, Regents.Keyfleet.Keys.ShardEvent do
      source_attribute :wallet_address
      destination_attribute :wallet
      public? false
    end

    has_many :check_ins, Regents.Keyfleet.Agents.CheckIn do
      public? false
    end

    # The wallets of the person this agent is paired with, each with the
    # person's account (`Regents.Account.Agents.PairedPersonWallet`). Read only
    # inside `paired_key`, which lets nothing of them out but a key's number.
    has_many :person_wallets, Regents.Account.Agents.PairedPersonWallet do
      source_attribute :wallet_address
      destination_attribute :agent_wallet
      public? false
    end
  end

  calculations do
    # Whether a World ID-verified person stands behind the agent. Who they are
    # stays private.
    calculate :human_backed, :boolean, expr(not is_nil(human_id)), public?: true

    # The picture a page shows beside the agent's name.
    calculate :avatar_src, :string, Regents.Keyfleet.Agents.Calculations.AvatarSrc do
      public? true
    end

    # When this agent was last seen in the fleet (`Regents.Keyfleet.Agents.CheckIn`).
    calculate :last_seen_at,
              :utc_datetime_usec,
              expr(
                first(check_ins,
                  field: :last_seen_at,
                  query: [filter: expr(fleet_id == ^arg(:fleet_id))]
                )
              ) do
      argument :fleet_id, :string, allow_nil?: false
      public? true
    end

    # Whether the agent is here in any of the fleets: its wallet holds one of
    # their keys, or an active shard of one, or it is paired with a person
    # who holds one. These are the ways an agent
    # acts as a key in a fleet (`Regents.Keyfleet.Keys.identity/2`).
    calculate :here,
              :boolean,
              expr(
                not is_nil(held_key(fleet_ids: ^arg(:fleet_ids))) or
                  exists(shards, fleet_id in ^arg(:fleet_ids) and active?) or
                  not is_nil(paired_key(fleet_ids: ^arg(:fleet_ids)))
              ) do
      argument :fleet_ids, {:array, :string}, allow_nil?: false
    end

    # The key the agent acts as in the fleet, by the same rule as
    # `Regents.Keyfleet.Keys.identity/2`: the lowest-numbered key its wallet holds,
    # else the key its person put it on (`Regents.Keyfleet.Keys.assigned_keys/3`),
    # else the key of its active shard, else the key the person it is paired
    # with writes as.
    calculate :key, :integer, Regents.Keyfleet.Agents.Calculations.Key do
      argument :fleet_id, :string, allow_nil?: false
      public? true
    end

    # The key of the active shard the agent holds in the fleet (a wallet
    # holds one shard in a fleet at a time).
    calculate :shard_key,
              :integer,
              expr(
                min(shards,
                  field: :token_id,
                  query: [filter: expr(fleet_id == ^arg(:fleet_id) and active?)]
                )
              ) do
      argument :fleet_id, :string, allow_nil?: false
    end

    # The lowest-numbered of the fleets' keys the agent's own wallet holds
    # now. Ownership records are read in SQL, as `KeyAttachment`'s own
    # current epoch is, since that table has no scope-free read to aggregate.
    calculate :held_key,
              :integer,
              expr(
                fragment(
                  """
                  (SELECT min(held.token_id)
                   FROM keyfleet_app.key_attachments AS held
                   WHERE held.owner_wallet = ? AND held.fleet_id = ANY(?)
                     AND held.ownership_epoch = (
                       SELECT max(epoch.ownership_epoch)
                       FROM keyfleet_app.key_attachments AS epoch
                       WHERE epoch.fleet_id = held.fleet_id AND epoch.token_id = held.token_id
                     ))
                  """,
                  wallet_address,
                  ^arg(:fleet_ids)
                )
              ) do
      argument :fleet_ids, {:array, :string}, allow_nil?: false
    end

    # The key the person this agent is paired with writes as
    # (`RegentAgents.PairedAgent`): the one they chose on the Account page while
    # any of their wallets holds it (`Regents.Keyfleet.Keys.PostingKey`), else the
    # lowest-numbered of the fleets' keys their wallets hold now. The person's
    # wallets are for trusted code only (their read admits the system actor
    # alone), so they are reached here through `person_wallets` without that
    # read, by the agent's own wallet alone, and only the key's number leaves.
    # Each wallet's keys are read in SQL, as `held_key`'s are, and each wallet
    # is looked up on its own: matched as a set, every key in the fleet was
    # read for every agent, 7 seconds for a full Regents Club.
    calculate :paired_key,
              :integer,
              expr(
                min(person_wallets,
                  expr:
                    fragment(
                      """
                      (SELECT min(held.token_id)
                       FROM keyfleet_app.key_attachments AS held
                       JOIN keyfleet_app.posting_keys AS chosen
                         ON chosen.fleet_id = held.fleet_id AND chosen.token_id = held.token_id
                       WHERE held.owner_wallet = ? AND chosen.human_account_id = ?
                         AND held.fleet_id = ANY(?)
                         AND held.ownership_epoch = (
                           SELECT max(epoch.ownership_epoch)
                           FROM keyfleet_app.key_attachments AS epoch
                           WHERE epoch.fleet_id = held.fleet_id AND epoch.token_id = held.token_id
                         ))
                      """,
                      wallet,
                      human_account_id,
                      ^arg(:fleet_ids)
                    ),
                  expr_type: :integer,
                  authorize?: false
                ) ||
                  min(person_wallets,
                    expr:
                      fragment(
                        """
                        (SELECT min(held.token_id)
                         FROM keyfleet_app.key_attachments AS held
                         WHERE held.owner_wallet = ? AND held.fleet_id = ANY(?)
                           AND held.ownership_epoch = (
                             SELECT max(epoch.ownership_epoch)
                             FROM keyfleet_app.key_attachments AS epoch
                             WHERE epoch.fleet_id = held.fleet_id AND epoch.token_id = held.token_id
                           ))
                        """,
                        wallet,
                        ^arg(:fleet_ids)
                      ),
                    expr_type: :integer,
                    authorize?: false
                  )
              ) do
      argument :fleet_ids, {:array, :string}, allow_nil?: false
    end
  end

  identities do
    identity :unique_wallet, [:wallet_address]
  end
end
