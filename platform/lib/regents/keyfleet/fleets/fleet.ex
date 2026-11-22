defmodule Regents.Keyfleet.Fleets.Fleet do
  @moduledoc """
  A fixed fleet with a stable machine identity and display name, and once it is
  deployed, the chain it lives on and its number in the Key collection
  (`chain_fleet_id`), the collection and the shard record every fleet shares,
  its own four contracts (its manager, which sells its Keys, its vote
  contract, treasury and reward ledger), the USDC its Keys are paid in, the
  REGENT token and staking contract Regents' share goes through, the
  Autolaunch factory its launch token comes from, the claims contract that
  holds Regents Club Keys for Passes that cannot take one, the hash of the
  trait table its Keys' traits are drawn from, and the hash and size of its
  card deck (`Regents.Keyfleet.Decks`).

  Every fleet here is a founding fleet, the first of its type, and a founding
  fleet's Keys 1 to its deck's size are dealt by number: Key N holds the
  deck's card N (`dealt?/2`), known from the deck as soon as the Key exists.
  Only a Key past the deck waits for its random draw.

  The site numbers a fleet's Keys 1, 2, 3 and on (`token_id` everywhere in the
  site). On the chain a Key's token id is the fleet's number times
  10,000,000,000 plus that Key number (`onchain_token_id/2`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Fleets,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # `KeyfleetKeys.TOKEN_ID_STRIDE`: a Key's token id is its fleet's number
  # times this, plus its Key number.
  @token_id_stride 10_000_000_000

  @addresses [
    :keys_address,
    :manager_address,
    :rewards_address,
    :votes_address,
    :treasury_address,
    :shards_address,
    :usdc_address,
    :regent_address,
    :regent_staking_address,
    :autolaunch_factory_address,
    :club_claims_address
  ]

  @deployment [:chain_id, :chain_fleet_id] ++
                @addresses ++ [:deployed_block, :trait_table_hash, :deck_hash, :deck_size]

  @doc "The fields a deployment records, every one of them required."
  def deployment_fields, do: @deployment

  @doc "Whether `number` can be a fleet's Key number: from 1 to 9,999,999,999."
  def key_number?(number), do: is_integer(number) and number > 0 and number < @token_id_stride

  @doc "The token id on the chain of the fleet's Key `key_number`."
  def onchain_token_id(%{chain_fleet_id: fleet}, key_number)
      when is_integer(fleet) and key_number > 0 and key_number < @token_id_stride,
      do: fleet * @token_id_stride + key_number

  @doc """
  The fleet's Key number of the chain's token id `token_id`: `{:ok, number}`,
  or `:foreign` for a token of another fleet.
  """
  def key_number(%{chain_fleet_id: fleet}, token_id) when is_integer(token_id) do
    case {div(token_id, @token_id_stride), rem(token_id, @token_id_stride)} do
      {^fleet, number} when number > 0 -> {:ok, number}
      _other -> :foreign
    end
  end

  @doc """
  Whether the fleet's Key `key_number` is dealt its card by number, the deck's
  card N for Key N, rather than drawn: every Key within the deck. A fleet not
  yet deployed has no deck, so none of its Keys is dealt.
  """
  def dealt?(%{deck_size: size}, key_number), do: is_integer(size) and key_number <= size

  postgres do
    table "fleets"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:id, "fleets_fixed_catalog",
        check:
          "id IN ('fibonacci_syndicate', 'fibonacci_cascade', 'fleet_tech_classic', 'fleet_tech_accelerant', 'regents_club')",
        message: "must identify one of the five fixed fleets"
      )

      # A deployment is recorded whole or not at all.
      check_constraint(:manager_address, "fleets_deployment_whole",
        check:
          "num_nulls(chain_id, chain_fleet_id, keys_address, manager_address, rewards_address, votes_address, treasury_address, shards_address, usdc_address, regent_address, regent_staking_address, autolaunch_factory_address, club_claims_address, deployed_block, trait_table_hash, deck_hash, deck_size) IN (0, 17)",
        message: "must record the whole deployment"
      )

      for field <- @addresses do
        check_constraint(field, "fleets_#{field}_shape", check: "#{field} ~ '^0x[0-9a-f]{40}$'")
      end

      check_constraint(:chain_fleet_id, "fleets_chain_fleet_id_positive",
        check: "chain_fleet_id > 0"
      )

      check_constraint(:deck_hash, "fleets_deck_hash_shape",
        check: "deck_hash ~ '^0x[0-9a-f]{64}$'"
      )

      check_constraint(:deck_size, "fleets_deck_size_positive", check: "deck_size > 0")

      check_constraint(:trait_table_hash, "fleets_trait_table_hash_shape",
        check: "trait_table_hash ~ '^0x[0-9a-f]{64}$'"
      )
    end
  end

  actions do
    defaults [:read]

    create :bootstrap do
      public? false
      accept [:id, :name]

      validate one_of(
                 :id,
                 ~w(fibonacci_syndicate fibonacci_cascade fleet_tech_classic fleet_tech_accelerant regents_club)
               )

      upsert? true
      upsert_fields [:name]
    end

    read :deployed do
      public? false
      filter expr(not is_nil(manager_address))
      prepare build(sort: [id: :asc])
    end

    # Binds the fleet to its deployment once. Recording the same deployment
    # again changes nothing; a different one is refused, and so is one whose
    # chain, collection, shard record, USDC, REGENT, staking contract,
    # Autolaunch factory, Regents Club claims contract or trait table differs
    # from another bound fleet's.
    update :record_deployment do
      public? false
      require_atomic? false

      accept @deployment
      require_attributes @deployment

      # Both run inside the action's transaction and read the fleets under
      # their row locks, so each compares against what is committed. The
      # wiring check goes first because it locks every fleet in id order;
      # locking this fleet alone first could deadlock with a recording of
      # another fleet.
      validate Regents.Keyfleet.Fleets.Validations.SharedWiring, before_action?: true
      validate Regents.Keyfleet.Fleets.Validations.SameDeployment, before_action?: true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action([:bootstrap, :record_deployment]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :chain_id, :integer, public?: true, constraints: [min: 1]

    # The fleet's number in the Key collection, which counts every fleet.
    attribute :chain_fleet_id, :integer, public?: true, constraints: [min: 1]

    for field <- @addresses do
      attribute field, :string,
        public?: true,
        constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
    end

    # The first block of the deployment, where reading its history starts.
    attribute :deployed_block, :integer, public?: true, constraints: [min: 0]

    # `keccak256` of the trait table file, byte for byte, as the fleet holds it.
    attribute :trait_table_hash, :string,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]

    # `keccak256` of the fleet's card deck file and how many cards it holds,
    # as the Key collection holds them: Keys 1 to `deck_size` are dealt its
    # cards.
    attribute :deck_hash, :string,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]

    attribute :deck_size, :integer, public?: true, constraints: [min: 1]
  end
end
