defmodule Regents.Keyfleet.Fleets do
  @moduledoc "The fixed fleet catalog."
  use Ash.Domain

  alias Regents.Keyfleet.Fleets.Fleet

  # The fleets in the order the site shows them. Club launches first; the
  # others show as coming soon until the founder opens them, one at a time,
  # by marking them `coming_soon?: false` here or by recording their
  # deployment. `card` is the fleet's type as its Keys' names print it; each
  # is the first fleet of its type.
  #
  # `path` is where the fleet's pages are on the site: its type and its number
  # within that type, so the next Classic is `/classic/2`. The Regents Club's
  # are where they have been since it opened. `sidebar` is how the fleet shows
  # in the site's sidebar: `:link` to its page, or `nil`, left out.
  @catalog [
    %{
      id: "fleet_tech_classic",
      path: "/classic/1",
      sidebar: :link,
      name: "Classic #1",
      card: "CLASSIC",
      type_number: 1,
      coming_soon?: true
    },
    %{
      id: "fibonacci_syndicate",
      path: "/syndicate/1",
      sidebar: nil,
      name: "Syndicate #1",
      card: "SYNDICATE",
      type_number: 1,
      coming_soon?: true
    },
    %{
      id: "fibonacci_cascade",
      path: "/cascade/1",
      sidebar: nil,
      name: "Cascade #1",
      card: "CASCADE",
      type_number: 1,
      coming_soon?: true
    },
    %{
      id: "fleet_tech_accelerant",
      path: "/accelerant/1",
      sidebar: nil,
      name: "Accelerant #1",
      card: "ACCELERANT",
      type_number: 1,
      coming_soon?: true
    },
    %{
      id: "regents_club",
      path: "/app/fleets/regents_club",
      sidebar: nil,
      name: "Regents Club",
      card: "REGENTS CLUB",
      type_number: 1,
      coming_soon?: true
    }
  ]

  resources do
    resource Regents.Keyfleet.Fleets.Fleet do
      define :list_fleets, action: :read
      define :get_fleet, action: :read, get_by: [:id], not_found_error?: false
      define :list_deployed_fleets, action: :deployed
      define :record_deployment, action: :record_deployment
    end
  end

  @doc """
  The fixed catalog's fleets as `%{id: id, path: path, sidebar: shown, name: name, card: card,
  type_number: number, coming_soon?: marked}`, in the order the site shows them. `type_number` is the
  contract's per-type set number, not its global fleet id. `coming_soon?` is the catalog's mark
  alone; `coming_soon?/2` says whether a fleet is coming soon.
  """
  def catalog, do: @catalog

  @doc "Where the fleet's pages are on the site, such as `/classic/1`."
  def path(fleet_id), do: Enum.find(@catalog, &(&1.id == fleet_id)).path

  @doc "The fleet's name, such as `Classic #1`."
  def name(fleet_id), do: Enum.find(@catalog, &(&1.id == fleet_id)).name

  @doc "The fleet whose pages hold the site path `path` (its own page or one under it), or nil."
  def at_path(path),
    do: Enum.find(@catalog, &(path == &1.path or String.starts_with?(path, &1.path <> "/")))

  @doc """
  A Key's name, on its card and in its metadata: the fleet's type, the
  fleet's number within its type and the Key's number, each number at least
  three digits, such as `CLASSIC—001—072` or `CLASSIC—001—1024`. A Regents
  Club Key is named for its Pass, with four digits: `REGENTS CLUB 0001` to
  `REGENTS CLUB 1998`.
  """
  def key_name("regents_club", token_id), do: "REGENTS CLUB " <> padded(token_id, 4)

  def key_name(fleet_id, token_id) do
    %{card: card, type_number: number} = Enum.find(@catalog, &(&1.id == fleet_id))
    Enum.join([card, padded(number, 3), padded(token_id, 3)], "—")
  end

  defp padded(number, digits),
    do: number |> Integer.to_string() |> String.pad_leading(digits, "0")

  @doc "The machine ids of the fixed catalog, in catalog order."
  def catalog_ids, do: Enum.map(@catalog, & &1.id)

  @doc """
  Whether the fleet `fleet_id`, recorded as `recorded` (or `nil` before the
  catalog is seeded), is coming soon: the catalog marks it so and no
  deployment is recorded for it. A coming-soon fleet shows its name and that
  it is coming soon, and nothing else: no price, no keys, no rooms and no
  way to join. Recording its deployment by hand opens it.
  """
  def coming_soon?(fleet_id, recorded) do
    Enum.any?(@catalog, &(&1.id == fleet_id and &1.coming_soon?)) and
      (recorded == nil or recorded.manager_address == nil)
  end

  @doc "The ids of the fleets that are not coming soon, in catalog order."
  def open_fleet_ids do
    recorded = Map.new(list_fleets!(), &{&1.id, &1})
    for %{id: id} <- @catalog, not coming_soon?(id, recorded[id]), do: id
  end

  @doc """
  Seeds the fixed catalog from trusted application setup code.

  Reruns preserve machine identities and restore canonical display names. The
  whole catalog commits together. Every fleet then has its first project,
  `general` (`Regents.Keyfleet.Projects.bootstrap_general!/1`), and the two projects
  it shares (`Regents.Keyfleet.Projects.bootstrap_shared!/1`). This internal entry
  point must never be exposed as a user action.
  """
  def bootstrap_catalog! do
    %Ash.BulkResult{records: fleets} =
      @catalog
      |> Enum.map(&Map.take(&1, [:id, :name]))
      |> Ash.bulk_create!(Fleet, :bootstrap,
        actor: %Regents.Account.Actors.System{},
        return_records?: true,
        return_errors?: true,
        stop_on_error?: true,
        transaction: :all,
        sorted?: true
      )

    :ok = Regents.Keyfleet.Projects.bootstrap_general!(Enum.map(fleets, & &1.id))
    :ok = Regents.Keyfleet.Projects.bootstrap_shared!(fleets)
    fleets
  end

  # The address the treasury names ETH by.
  @native "0x0000000000000000000000000000000000000000"

  # The deployed record names each fleet's type; the catalog's fleets are the
  # first of each type.
  @manifest_slots %{
    "syndicate" => "fibonacci_syndicate",
    "cascade" => "fibonacci_cascade",
    "classic" => "fleet_tech_classic",
    "accelerant" => "fleet_tech_accelerant",
    "regentsClub" => "regents_club"
  }

  @doc "The type of the fleet `fleet_id`, such as `classic`."
  def slot(fleet_id) do
    {slot, ^fleet_id} = Enum.find(@manifest_slots, &(elem(&1, 1) == fleet_id))
    slot
  end

  @doc """
  Binds the catalog's fleets to the deployment a deployed record describes,
  the JSON `contracts/script/RecordKeyfleets.s.sol` writes, from trusted
  operator code, and returns the fleets bound. Each fleet the record holds
  that is the first of its type is the catalog's fleet of that type; any
  other fleet the record holds is not the catalog's and is left out.

  The treasury splits ETH, REGENT and USDC from the start, in that order, so
  a fleet whose `splitAssets` begin otherwise matches no clause.

  Recording the same record again changes nothing; a record naming other
  contracts for a bound fleet is refused, and so is one whose chain,
  collection, shard record, USDC, REGENT, staking contract, Autolaunch
  factory, Regents Club claims contract or trait table differs from a fleet
  already bound.
  """
  def record_manifest!(%{
        "chainId" => chain_id,
        "deploymentBlock" => block,
        "collection" => %{"address" => keys},
        "shards" => %{"address" => shards},
        "usdc" => usdc,
        "regent" => regent,
        "regentStaking" => regent_staking,
        "autolaunchFactory" => autolaunch_factory,
        "clubClaims" => %{"address" => club_claims},
        "traitTableHash" => trait_table_hash,
        "fleets" => fleets
      })
      when is_integer(chain_id) and is_integer(block) do
    bootstrap_catalog!()

    shared = %{
      chain_id: chain_id,
      keys_address: String.downcase(keys),
      shards_address: String.downcase(shards),
      usdc_address: String.downcase(usdc),
      regent_address: String.downcase(regent),
      regent_staking_address: String.downcase(regent_staking),
      autolaunch_factory_address: String.downcase(autolaunch_factory),
      club_claims_address: String.downcase(club_claims),
      deployed_block: block,
      trait_table_hash: String.downcase(trait_table_hash)
    }

    for {number, %{"type" => type, "typeNumber" => 1} = fleet} <- Enum.sort(fleets),
        fleet_id = Map.fetch!(@manifest_slots, type) do
      fleet_id
      |> get_fleet!()
      |> record_deployment!(deployment(shared, number, fleet, regent, usdc),
        actor: %Regents.Account.Actors.System{}
      )
    end
  end

  defp deployment(shared, number, fleet, regent, usdc) do
    %{
      "manager" => manager,
      "votes" => votes,
      "treasury" => treasury,
      "rewards" => rewards,
      "deckHash" => deck_hash,
      "deckSize" => deck_size,
      "splitAssets" => [@native, ^regent, ^usdc | _admitted_later]
    } = fleet

    Map.merge(shared, %{
      chain_fleet_id: String.to_integer(number),
      manager_address: String.downcase(manager),
      votes_address: String.downcase(votes),
      treasury_address: String.downcase(treasury),
      rewards_address: String.downcase(rewards),
      deck_hash: String.downcase(deck_hash),
      deck_size: deck_size
    })
  end
end
