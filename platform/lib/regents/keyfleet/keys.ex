defmodule Regents.Keyfleet.Keys do
  @moduledoc """
  Key ownership, reveals and ended draw waits, shards, agent voting, presence
  and edit restrictions projected from contract events, and which Keys have
  their card picture.
  """
  use Ash.Domain

  import Ecto.Query, only: [from: 2, subquery: 1, union: 2, union_all: 2]

  require Ash.Query
  require Logger

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Decks
  alias Regents.Keyfleet.Fleets.Fleet
  alias Regents.Keyfleet.Keys.AgentKey

  resources do
    resource Regents.Keyfleet.Keys.KeyAttachment do
      define :record_epoch, action: :record_epoch
      define :key_history, action: :history, args: [:fleet_id, :token_id]
      define :current_key, action: :current, args: [:fleet_id, :token_id], not_found_error?: false

      define :held_identity_key,
        action: :identity_in_fleet,
        args: [:fleet_id, :owner_wallets],
        not_found_error?: false

      define :newest_key_change,
        action: :newest_in_fleet,
        args: [:fleet_id],
        not_found_error?: false

      define :keys_in_fleet, action: :current_in_fleet, args: [:fleet_id]
      define :keys_held_in_fleet, action: :held_in_fleet, args: [:fleet_id, :owner_wallets]
      define :keys_held_everywhere, action: :held_everywhere, args: [:owner_wallets]

      define :recorded_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :epochs_recorded_since, action: :recorded_since, args: [:fleet_id, :after_seq]

      define :epochs_recorded_before,
        action: :recorded_before,
        args: [:fleet_id, :before_seq, :limit]

      define :epochs_by_record_seq, action: :by_record_seq, args: [:fleet_id, :record_seqs]

      define :lowest_keys_held, action: :lowest_held, args: [:fleet_id, :owner_wallets]
    end

    resource Regents.Keyfleet.Keys.KeyReveal do
      define :record_reveal, action: :record
      define :get_reveal, action: :read, get_by: [:fleet_id, :token_id], not_found_error?: false
      define :reveals_recorded_since, action: :recorded_since, args: [:fleet_id, :after_seq]
      define :reveals_of_keys, action: :of_keys, args: [:fleet_id, :token_ids]

      define :reveals_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]
    end

    resource Regents.Keyfleet.Keys.KeyRevealExpiry do
      define :record_reveal_expiry, action: :record

      define :get_reveal_expiry,
        action: :read,
        get_by: [:fleet_id, :token_id],
        not_found_error?: false

      define :reveal_expiries_recorded_since,
        action: :recorded_since,
        args: [:fleet_id, :after_seq]

      define :reveal_expiries_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]
    end

    resource Regents.Keyfleet.Keys.KeyPicture do
      define :record_picture, action: :record

      define :get_picture,
        action: :read,
        get_by: [:fleet_id, :token_id, :seed],
        not_found_error?: false

      define :pictures_of_keys, action: :of_keys, args: [:fleet_id, :token_ids]
    end

    resource Regents.Keyfleet.Keys.ShardEvent do
      define :record_shard_event, action: :record

      define :shard_events_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :shard_events_recorded_since, action: :recorded_since, args: [:fleet_id, :after_seq]

      define :shard_events_recorded_before,
        action: :recorded_before,
        args: [:fleet_id, :before_seq, :limit]

      define :active_shard,
        action: :active_of_key_held_by,
        args: [:fleet_id, :token_id, :wallet],
        not_found_error?: false

      define :active_shards_held_by, action: :active_held_by, args: [:wallet]
      define :active_shards_of_keys, action: :active_of_keys, args: [:fleet_id, :token_ids]
      define :active_shards_in_fleet, action: :active_in_fleet, args: [:fleet_id]
      define :keys_with_shards, action: :keys_with_shards, args: [:fleet_id]

      define :shards_issued_by_owner,
        action: :issued_by_owner,
        args: [:fleet_id, :token_id, :owner]
    end

    resource Regents.Keyfleet.Keys.AgentVoting do
      define :record_agent_voting, action: :record

      define :agent_voting_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :agent_voting_recorded_since, action: :recorded_since, args: [:fleet_id, :after_seq]

      define :latest_agent_voting,
        action: :latest_of_key,
        args: [:fleet_id, :token_id],
        not_found_error?: false
    end

    resource Regents.Keyfleet.Keys.Presence do
      define :record_presence, action: :record

      define :presences_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :presences_marked_before,
        action: :marked_before,
        args: [:fleet_id, :before_block, :before_log, :limit]
    end

    resource Regents.Keyfleet.Keys.PostingKey do
      define :choose_posting_key, action: :choose, args: [:fleet_id, :token_id]
      define :posting_key, action: :in_fleet, args: [:fleet_id], not_found_error?: false

      define :posting_keys_of_accounts,
        action: :of_accounts,
        args: [:fleet_id, :human_account_ids]
    end

    resource Regents.Keyfleet.Keys.AgentKey do
      define :assign_agent, action: :assign, args: [:fleet_id, :token_id, :agent_wallet]
      define :release_agent_key, action: :release
      define :agent_keys_of_person, action: :of_person
      define :agent_keys_of_agents, action: :of_agents, args: [:fleet_id, :wallets]
    end

    resource Regents.Keyfleet.Keys.EditsRestriction do
      define :record_edits_restriction, action: :record

      define :edits_restrictions_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :edits_restrictions_recorded_since,
        action: :recorded_since,
        args: [:fleet_id, :after_seq]

      define :latest_edits_restrictions,
        action: :latest_for_keys,
        args: [:fleet_id, :token_ids]
    end
  end

  @doc """
  The seed Key `token_id` of `fleet` draws its card's traits from, or `nil`
  while it has none. A Key within the deck is dealt the deck's card by number,
  Key N card N − 1 (`Regents.Keyfleet.Fleets.Fleet.dealt?/2`); a Key past it shows its
  recorded reveal's seed, once the reveal is read. Ask only for a Key that has
  been minted: a dealt card is never shown before its Key exists.
  """
  def card_seed(%{id: fleet_id, deck_hash: deck_hash} = fleet, token_id) do
    if Fleet.dealt?(fleet, token_id) do
      elem(Decks.deck!(deck_hash).cards, token_id - 1)
    else
      case get_reveal!(fleet_id, token_id) do
        nil -> nil
        reveal -> reveal.seed
      end
    end
  end

  @doc """
  The seed of each of the minted Keys `token_ids` of `fleet` that has one, by
  Key number (`card_seed/2`), in one read however many Keys are asked for, a
  hundred at most.
  """
  def card_seeds(%{id: fleet_id, deck_hash: deck_hash} = fleet, token_ids) do
    {dealt, drawn} = Enum.split_with(token_ids, &Fleet.dealt?(fleet, &1))

    dealt =
      case dealt do
        [] -> %{}
        dealt -> Map.new(dealt, &{&1, elem(Decks.deck!(deck_hash).cards, &1 - 1)})
      end

    for reveal <- reveals_of_keys!(fleet_id, drawn),
        into: dealt,
        do: {reveal.token_id, reveal.seed}
  end

  @doc "Whether the key's workspace edits are restricted by a vote of the fleet right now."
  def edits_restricted?(fleet_id, token_id, opts \\ []) do
    with {:ok, latest} <- latest_edits_restrictions(fleet_id, [token_id], opts) do
      {:ok, match?([%{restricted: true}], latest)}
    end
  end

  @doc """
  Whether `wallet` governs the fleet's key `token_id` now, as the shards
  contract's `mayGovern` answers it on the chain, read from Keyfleet's record
  of it: the wallet holding the key does; another wallet does while it holds
  an active shard of the key and the key's agent voting is on. A new owner
  starts with agent voting on, and only the owner turns it off for the
  ownership it is in (`Regents.Keyfleet.Keys.AgentVoting`).
  """
  def governs?(fleet_id, token_id, wallet) do
    case current_key!(fleet_id, token_id) do
      %{owner_wallet: ^wallet} ->
        true

      %{ownership_epoch: epoch} ->
        active_shard!(fleet_id, token_id, wallet) != nil and
          agent_voting?(fleet_id, token_id, epoch)

      nil ->
        false
    end
  end

  defp agent_voting?(fleet_id, token_id, epoch) do
    not match?(
      %{allowed: false, ownership_epoch: ^epoch},
      latest_agent_voting!(fleet_id, token_id)
    )
  end

  @doc """
  Where a fleet's pages hear which of its keys have just changed: sold, changed
  hands, revealed, a shard issued or ended, agent voting turned on or off,
  edits restricted or allowed, an agent put on a Key, or a person's posting
  Key chosen, as
  `{:keys_changed, fleet_id, token_ids}`; and which were just marked present,
  as `{:keys_present, fleet_id, token_ids}`.
  """
  def topic(fleet_id), do: "keyfleet:fleet:#{fleet_id}:keys"

  @doc """
  The key `actor` is in a fleet today, as `%{token_id: token_id, wallet: wallet}`,
  or `nil` when it neither holds one of the fleet's keys nor has a shard of one.

  Keys rank by the order they were sold, the first key sold ranking highest. A
  person is the key they chose to write as on the Account page while their
  wallets hold it (`Regents.Keyfleet.Keys.PostingKey`), else the highest-ranked key
  their wallets hold, and `wallet` is the one holding it. An agent is the
  highest-ranked key its wallet holds, with its own wallet; else the key its
  person put it on (`Regents.Keyfleet.Keys.AgentKey`), while it stands there
  (`placed_on?/3`) and this pairing lasts, with `for_person: true` and the person's wallet holding
  it; else the highest-ranked key it holds an active shard of, with its own
  wallet. Everything either writes in the fleet is written as that key.

  An agent with none of these, paired with a person whose account is here
  (`Regents.Account.Actors.Agent`'s `pairing`), is that person's key, with
  `for_person: true`. Whatever an agent writes with `for_person: true` is the
  person's, marked as the agent's.
  """
  def identity(%Human{wallet_addresses: [_ | _] = wallets} = actor, fleet_id) do
    case chosen_key(actor, fleet_id) || held_identity_key!(fleet_id, wallets, actor: actor) do
      nil -> nil
      key -> %{token_id: key.token_id, wallet: key.owner_wallet}
    end
  end

  def identity(%Agent{} = actor, fleet_id) do
    case Agent.refresh(actor) do
      {:ok, actor} -> agent_identity(actor, fleet_id)
      _ -> nil
    end
  end

  def identity(_actor, _fleet_id), do: nil

  # Its own Key, then the Key its person put it on, then a shard, then its
  # person's Key.
  defp agent_identity(%Agent{wallet_address: wallet} = actor, fleet_id) do
    case held_identity_key!(fleet_id, [wallet], actor: actor) do
      %{token_id: token_id} -> %{token_id: token_id, wallet: wallet}
      nil -> assigned_identity(actor, fleet_id)
    end
  end

  defp assigned_identity(actor, fleet_id) do
    case assigned_key!(actor, fleet_id) do
      %{token_id: token_id, owner_wallet: owner} ->
        %{token_id: token_id, wallet: owner, for_person: true}

      nil ->
        shard_identity(actor, fleet_id)
    end
  end

  defp shard_identity(%Agent{wallet_address: wallet} = actor, fleet_id) do
    case active_shard_in(fleet_id, wallet, actor) do
      %{token_id: token_id} -> %{token_id: token_id, wallet: wallet}
      nil -> for_person(actor.pairing, fleet_id)
    end
  end

  @doc """
  The Key each agent with one of `wallets` (lowercase) is on in the fleet:
  the Key its person put it on (`Regents.Keyfleet.Keys.AgentKey`), by the wallet's
  current pairing, while it stands there (`placed_on?/3`), as the Key's
  current ownership record. `{:ok, %{wallet => key}}`, an agent on no Key
  left out, or `{:error, error}`. However many agents, it is three reads, and
  one more for each hundred people beyond the first.

  This is the one rule for it: an agent acting (`assigned_key/3`) and the
  agents a fleet lists (`Regents.Keyfleet.Agents.AgentProfile`'s `:key`) both read
  it here. `opts` go with each read, such as a check's time limit.
  """
  def assigned_keys(fleet_id, wallets, opts \\ [])

  def assigned_keys(_fleet_id, [], _opts), do: {:ok, %{}}

  def assigned_keys(fleet_id, wallets, opts) do
    system = [actor: %Regents.Account.Actors.System{}] ++ opts

    case agent_keys_of_agents(fleet_id, wallets, system) do
      {:ok, []} -> {:ok, %{}}
      {:ok, placed} -> held_by_their_people(fleet_id, placed, system)
      {:error, error} -> {:error, error}
    end
  end

  defp held_by_their_people(fleet_id, placed, system) do
    token_ids = Enum.map(placed, & &1.token_id)

    with {:ok, accounts} <- accounts_of(placed, system),
         wallets_of = Map.new(accounts, &{&1.id, Human.for_account(&1).wallet_addresses}),
         {:ok, held} <-
           keys_held_in_fleet(
             fleet_id,
             wallets_of |> Map.values() |> Enum.concat(),
             system ++
               [
                 query:
                   Ash.Query.filter(Regents.Keyfleet.Keys.KeyAttachment, token_id in ^token_ids)
               ]
           ) do
      held = Map.new(held, &{&1.token_id, &1})

      on_keys =
        for %{agent_wallet: wallet, human_account_id: account} = row <- placed,
            key = held[row.token_id],
            placed_on?(row, key, Map.get(wallets_of, account, [])),
            into: %{},
            do: {wallet, key}

      {:ok, on_keys}
    end
  end

  # The accounts of the people who put those agents on their Keys, a hundred
  # to a read.
  defp accounts_of(placed, system) do
    placed
    |> Enum.map(& &1.human_account_id)
    |> Enum.uniq()
    |> Enum.chunk_every(100)
    |> Enum.reduce_while({:ok, []}, fn ids, {:ok, read} ->
      case Regents.Account.Accounts.accounts_by_ids(ids, system) do
        {:ok, accounts} -> {:cont, {:ok, accounts ++ read}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc """
  Whether the agent `row` (`Regents.Keyfleet.Keys.AgentKey`) puts on its Key still
  stands, given `key`, that Key's current ownership record (or nil), and the
  person's `wallets`: one of them holds the Key, and it has not changed hands
  since the row was saved. A Key that changes hands, even between the
  person's own wallets or back to them, has no agent on it. This is the one
  rule; every reader of who is on which Key asks it.
  """
  def placed_on?(
        %{token_id: token_id, ownership_epoch: epoch},
        %{token_id: token_id, ownership_epoch: epoch, owner_wallet: owner},
        wallets
      ),
      do: owner in wallets

  def placed_on?(_row, _key, _wallets), do: false

  @doc """
  The Key `agent`'s person put it on in the fleet, by `assigned_keys/3`:
  `{:ok, key}`, `{:ok, nil}` when there is none, or `{:error, error}`.
  """
  def assigned_key(agent, fleet_id, opts \\ [])

  def assigned_key(%Agent{pairing: %Human{}, wallet_address: wallet}, fleet_id, opts) do
    with {:ok, keys} <- assigned_keys(fleet_id, [wallet], opts), do: {:ok, keys[wallet]}
  end

  def assigned_key(_agent, _fleet_id, _opts), do: {:ok, nil}

  @doc "`assigned_key/3`, raising when the read fails."
  def assigned_key!(agent, fleet_id) do
    case assigned_key(agent, fleet_id) do
      {:ok, key} -> key
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  @doc """
  The Privy user of the person `actor` speaks for: a signed-in person's own,
  or the person a paired agent is paired with. `{:ok, privy_user_id}`, or
  `:error` for anyone else.
  """
  def person_privy_id(%Agent{pairing: %Human{}, privy_user_id: person}) when is_binary(person),
    do: {:ok, person}

  def person_privy_id(%Human{human_account_id: account_id}) do
    case Regents.Account.Accounts.accounts_by_ids!([account_id],
           actor: %Regents.Account.Actors.System{}
         ) do
      [%{privy_user_id: person}] -> {:ok, person}
      _no_account -> :error
    end
  end

  def person_privy_id(_actor), do: :error

  @doc """
  The agents paired with the person `actor` speaks for now, oldest pairing
  first, each `%{id: pairing_id, name: name, wallet: wallet}`
  (`RegentAgents.pairing_histories/1`); none for anyone else.
  """
  def person_agents(actor) do
    with {:ok, person} <- person_privy_id(actor),
         {:ok, pairings} <- RegentAgents.pairing_histories(person) do
      for %{revoked_at: nil} = pairing <- pairings, do: Map.take(pairing, [:id, :name, :wallet])
    else
      :error -> []
    end
  end

  @doc """
  Which of the person's `agents` (each with its pairing `id`, as
  `person_agents/1` gives them) are on each of the Keys their wallets hold now
  (`Regents.Keyfleet.Keys.AgentKey`), as `%{{fleet_id, token_id} => agents}`, in the
  order of `agents`, read in one go for every fleet, for the person or an
  agent paired with them. An agent that no longer stands on its Key
  (`placed_on?/3`), or has since been unpaired, is left out, and so is a Key
  with none.
  """
  def agents_on_keys(actor, agents) do
    case {person_wallets(actor), agents} do
      {[], _agents} -> %{}
      {_wallets, []} -> %{}
      {wallets, agents} -> agents_on_held_keys(actor, wallets, agents)
    end
  end

  defp agents_on_held_keys(actor, wallets, agents) do
    by_id = Map.new(agents, &{&1.id, &1})

    held =
      Map.new(keys_held_everywhere!(wallets, actor: actor), &{{&1.fleet_id, &1.token_id}, &1})

    order = agents |> Enum.with_index() |> Map.new(fn {agent, index} -> {agent.id, index} end)

    on_keys =
      for assigned <- agent_keys_of_person!(actor: actor),
          key = {assigned.fleet_id, assigned.token_id},
          placed_on?(assigned, held[key], wallets),
          agent = by_id[assigned.paired_agent_id],
          do: {key, agent}

    on_keys
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, on_key} -> {key, Enum.sort_by(on_key, &order[&1.id])} end)
  end

  @doc """
  The person `actor` takes the agent with pairing `pairing_id` off the Key it
  is on in the fleet (`Regents.Keyfleet.Keys.AgentKey`'s `:release`). `:ok`, also when
  it is on none, or `{:error, error}`; only the person may.
  """
  def release_agent(fleet_id, pairing_id, opts) do
    query = Ash.Query.filter(AgentKey, fleet_id == ^fleet_id and paired_agent_id == ^pairing_id)

    case agent_keys_of_person(Keyword.put(opts, :query, query)) do
      {:ok, []} -> :ok
      {:ok, [row]} -> release_agent_key(row, opts)
      {:error, error} -> {:error, error}
    end
  end

  @doc "The wallets of the person `actor` speaks for: their own, or a paired agent's person's."
  def person_wallets(%Human{wallet_addresses: wallets}), do: wallets
  def person_wallets(%Agent{pairing: %Human{wallet_addresses: wallets}}), do: wallets
  def person_wallets(_actor), do: []

  # The key the person chose to write as, while one of their wallets holds it.
  defp chosen_key(%Human{wallet_addresses: wallets} = actor, fleet_id) do
    with %{token_id: token_id} <- posting_key!(fleet_id, actor: actor),
         %{owner_wallet: owner} = key <- current_key!(fleet_id, token_id, actor: actor),
         true <- owner in wallets do
      key
    else
      _not_held -> nil
    end
  end

  defp for_person(%Human{} = person, fleet_id) do
    case identity(person, fleet_id) do
      nil -> nil
      identity -> Map.put(identity, :for_person, true)
    end
  end

  defp for_person(_missing, _fleet_id), do: nil

  @doc """
  Every key `actor` may act as in a fleet today, lowest first, each as
  `%{token_id: token_id, ownership_epoch: epoch, wallet: wallet, for_person: boolean}`,
  the epoch being the key's current one, by the same rule
  as `identity/2`: a person is every key their wallets hold, with the wallet
  holding it. An agent is every key its wallet holds, with its own wallet,
  and then no other; an agent whose wallet holds none is every key it holds
  an active shard of, with its own wallet, and the key its person put it on
  while it stands there (`placed_on?/3`), `for_person: true` with the wallet
  holding it; an agent with none of these, paired with a person here, is
  that person's keys, `for_person: true` (`agent_keys/3`). So an agent on a
  key acts as that key alone, and agents on different keys stay apart.
  Nobody else is any key. Direct messages read and send as these keys
  (`Regents.Keyfleet.Dms`): a key's new holder sees only messages from when they got it.
  """
  def held_keys(%Human{wallet_addresses: [_ | _] = wallets} = actor, fleet_id) do
    for key <- keys_held_in_fleet!(fleet_id, wallets, actor: actor),
        do: %{
          token_id: key.token_id,
          ownership_epoch: key.ownership_epoch,
          wallet: key.owner_wallet,
          for_person: false
        }
  end

  def held_keys(%Agent{} = actor, fleet_id) do
    case Agent.refresh(actor) do
      {:ok, actor} -> agent_keys!(actor, fleet_id)
      _ -> []
    end
  end

  def held_keys(_actor, _fleet_id), do: []

  @doc """
  Every key the agent `actor` acts as in the fleet today, lowest first, as
  `held_keys/2` gives them. A wallet that holds one of the fleet's keys acts
  as its own keys alone, never as a shard's key or as its person. An agent
  whose wallet holds none acts as the key its person put it on and every
  key it holds an active shard of; an agent with neither, paired with a
  person here, as its person's keys.

  This is the one rule for it: the workspace asks it for the key a write
  names (`Regents.Keyfleet.Graph.Checks.KeyActor`) and direct messages list it
  (`held_keys/2`). `opts` go with each read, such as a check's time limit.
  `{:ok, keys}` or `{:error, error}`.
  """
  def agent_keys(%Agent{wallet_address: wallet} = actor, fleet_id, opts \\ []) do
    case keys_held_in_fleet(fleet_id, [wallet], [actor: actor] ++ opts) do
      {:ok, []} -> delegated_keys(actor, fleet_id, opts)
      {:ok, own} -> {:ok, Enum.map(own, &agent_key(&1, wallet, false))}
      {:error, error} -> {:error, error}
    end
  end

  defp agent_keys!(actor, fleet_id) do
    case agent_keys(actor, fleet_id) do
      {:ok, keys} -> keys
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  # The Key its person put it on and its shards' Keys, each once, with the
  # wallet holding it; else its person's Keys.
  defp delegated_keys(%Agent{wallet_address: wallet} = actor, fleet_id, opts) do
    with {:ok, assigned} <- assigned_key(actor, fleet_id, opts),
         {:ok, shards} <- active_shards_held_by(wallet, [actor: actor] ++ opts) do
      assigned = for key <- List.wrap(assigned), do: agent_key(key, key.owner_wallet, true)
      sharded = for %{fleet_id: ^fleet_id} = shard <- shards, do: agent_key(shard, wallet, false)

      (assigned ++ sharded)
      |> Enum.sort_by(& &1.token_id)
      |> Enum.uniq_by(& &1.token_id)
      |> case do
        [] -> person_keys(actor.pairing, fleet_id, opts)
        keys -> {:ok, keys}
      end
    end
  end

  @doc """
  Each of `token_ids`' last presence record in the fleet, as `%{token_id =>
  record}`, or its last one before `{block_number, log_index}`. A Key with none
  isn't in the map.
  """
  def last_presence(fleet_id, token_ids, before \\ nil) do
    Regents.Keyfleet.Keys.Presence
    |> Ash.Query.filter(fleet_id == ^fleet_id and token_id in ^token_ids)
    |> presence_before(before)
    |> Ash.Query.distinct(:token_id)
    |> Ash.Query.distinct_sort(block_number: :desc, log_index: :desc)
    |> Ash.read!()
    |> Map.new(&{&1.token_id, &1})
  end

  defp presence_before(query, nil), do: query

  defp presence_before(query, {block, log}) do
    Ash.Query.filter(
      query,
      block_number < ^block or (block_number == ^block and log_index < ^log)
    )
  end

  @doc """
  How many of the fleet's Keys a proposal opening now would count, and how many
  of those have a day or less left (see the `present` and `expiring`
  calculations of `Regents.Keyfleet.Keys.KeyAttachment`), as `{:ok, %{present, expiring}}`,
  or `{:error, failure}` when the database doesn't answer (see `Regents.Keyfleet.Count`).
  """
  def presence_counts(fleet_id) do
    query =
      Ash.Query.for_read(Regents.Keyfleet.Keys.KeyAttachment, :present_in_fleet, %{
        fleet_id: fleet_id
      })

    with {:ok, present} <- Regents.Keyfleet.Count.of(query),
         {:ok, expiring} <- query |> Ash.Query.filter(expiring) |> Regents.Keyfleet.Count.of() do
      {:ok, %{present: present, expiring: expiring}}
    end
  end

  @doc """
  How many addresses hold at least one of the fleet's keys today
  (`holders`), and how many of them hold a key that did something since
  `since` (`online`): a post in a room or on a key's wall, a direct message,
  a poll started or voted in, or a check-in or contribution from an agent
  acting as the key. `{:ok, %{holders: n, online: n}}`, or `{:error, failure}`
  when the database doesn't answer.
  """
  def count_holders(fleet_id, since) do
    acted =
      Enum.uniq(
        acted_keys(fleet_id, since) ++ Regents.Keyfleet.Agents.keys_active_since!(fleet_id, since)
      )

    with {:ok, holders} <- count_owners(fleet_id, nil),
         {:ok, online} <- count_owners(fleet_id, acted),
         do: {:ok, %{holders: holders, online: online}}
  rescue
    failure in [Ash.Error.Unknown, Postgrex.Error, DBConnection.ConnectionError] ->
      Logger.warning("Counting the holders of #{fleet_id} failed: " <> Exception.message(failure))
      {:error, failure}
  end

  @doc """
  The people holding the fleet's keys today, most keys first, leaving out the
  addresses in `left_out`: `limit` of them from `offset`. A person is a Regent
  account with every address it links counted together; an address no account
  links is a holder of its own. Each is `%{account_id: id_or_nil, wallets:
  wallets, count: count}`, its wallets lowest first; holders with as many keys
  are ordered by their lowest wallet.
  """
  def holders(fleet_id, left_out, offset, limit) do
    from(key in subquery(owned(fleet_id)),
      left_join: linked in subquery(linked_wallets()),
      on: linked.wallet == key.owner_wallet,
      where: key.owner_wallet not in ^left_out,
      group_by: fragment("coalesce(?::text, ?)", linked.account_id, key.owner_wallet),
      order_by: [desc: count(), asc: min(key.owner_wallet)],
      offset: ^offset,
      limit: ^limit,
      select: %{
        account_id: max(linked.account_id),
        wallets: fragment("array_agg(DISTINCT ? ORDER BY ?)", key.owner_wallet, key.owner_wallet),
        count: count()
      }
    )
    # Ownership is public, and so is every address a Regent account links, so
    # keys are counted by person here directly.
    |> Regents.Repo.all()
  end

  @doc "The id of the Regent account linking `wallet`, as `holders/4` counts it, or nil."
  def holder_account_id(wallet) do
    from(linked in subquery(linked_wallets()),
      where: linked.wallet == ^String.downcase(wallet),
      select: linked.account_id
    )
    # Every address a Regent account links is public, as in holders/4.
    |> Regents.Repo.one()
  end

  # Every address a Regent account links, lowercase, with the account it
  # belongs to; an address two accounts claim goes to the older one.
  defp linked_wallets do
    from(
      linked in fragment("""
      SELECT lower(wallet) AS wallet, min(account.id) AS account_id
      FROM regent_names.platform_human_users AS account
      CROSS JOIN LATERAL unnest(account.wallet_addresses || account.wallet_address) AS wallet
      WHERE wallet IS NOT NULL
      GROUP BY lower(wallet)
      """),
      select: %{wallet: linked.wallet, account_id: linked.account_id}
    )
  end

  @doc """
  The lowest `shown` key numbers each of `wallets` holds in the fleet today,
  as `%{wallet => token_ids}`, lowest first.
  """
  def lowest_held(fleet_id, wallets, shown) do
    ranked =
      from(key in subquery(owned(fleet_id)),
        where: key.owner_wallet in ^wallets,
        select: %{
          wallet: key.owner_wallet,
          token_id: key.token_id,
          place: over(row_number(), partition_by: key.owner_wallet, order_by: key.token_id)
        }
      )

    from(key in subquery(ranked),
      where: key.place <= ^shown,
      order_by: [key.wallet, key.token_id],
      select: {key.wallet, key.token_id}
    )
    # Ownership is public; a window over each holder's Keys is read here directly.
    |> Regents.Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  Which of `wallets` hold a key of the fleet with a vote now (see the
  `present` calculation of `Regents.Keyfleet.Keys.KeyAttachment`).
  """
  def present_holders(fleet_id, wallets) do
    Regents.Keyfleet.Keys.KeyAttachment
    |> Ash.Query.for_read(:present_in_fleet, %{fleet_id: fleet_id})
    |> Ash.Query.filter(owner_wallet in ^wallets)
    |> Ash.Query.select([:owner_wallet])
    |> Ash.read!()
    |> MapSet.new(& &1.owner_wallet)
  end

  @doc """
  Which of `wallets` hold a key of the fleet that has no vote now (see the
  `idle` calculation of `Regents.Keyfleet.Keys.KeyAttachment`). A newly sold key
  waiting for its automatic start is not idle.
  """
  def idle_holders(fleet_id, wallets) do
    Regents.Keyfleet.Keys.KeyAttachment
    |> Ash.Query.for_read(:held_in_fleet, %{fleet_id: fleet_id, owner_wallets: wallets})
    |> Ash.Query.filter(idle)
    |> Ash.read!()
    |> MapSet.new(& &1.owner_wallet)
  end

  @doc """
  When each of `wallets` last did something in the fleet with a key it holds
  today, since it came to hold it: a check-in, a post, a direct message, or a
  poll started or voted in. `%{wallet => at}`, leaving out the wallets that
  have done none of these.
  """
  def last_active(fleet_id, wallets) do
    held = from(key in subquery(owned(fleet_id)), where: key.owner_wallet in ^wallets)

    renewed =
      from(p in "key_presences",
        prefix: ^Regents.Keyfleet.schema(),
        join: key in subquery(held),
        on: p.token_id == key.token_id and p.ownership_epoch == key.ownership_epoch,
        where: p.fleet_id == ^fleet_id and p.kind == "present",
        select: %{wallet: key.owner_wallet, at: type(p.at, :naive_datetime_usec)}
      )

    posted =
      from(m in "messages",
        prefix: ^Regents.Keyfleet.schema(),
        join: key in subquery(held),
        on: m.as_key == key.token_id and m.inserted_at >= key.observed_at,
        where: m.fleet_id == ^fleet_id,
        select: %{wallet: key.owner_wallet, at: m.inserted_at}
      )

    messaged =
      from(d in "dm_messages",
        prefix: ^Regents.Keyfleet.schema(),
        join: key in subquery(held),
        on: d.from_token_id == key.token_id and d.inserted_at >= key.observed_at,
        where: d.fleet_id == ^fleet_id,
        select: %{wallet: key.owner_wallet, at: d.inserted_at}
      )

    started =
      from(p in "polls",
        prefix: ^Regents.Keyfleet.schema(),
        join: key in subquery(held),
        on: p.started_by_key == key.token_id and p.inserted_at >= key.observed_at,
        where: p.fleet_id == ^fleet_id,
        select: %{wallet: key.owner_wallet, at: p.inserted_at}
      )

    voted =
      from(v in "poll_votes",
        prefix: ^Regents.Keyfleet.schema(),
        join: p in "polls",
        prefix: ^Regents.Keyfleet.schema(),
        on: p.id == v.poll_id,
        join: key in subquery(held),
        on: v.token_id == key.token_id and v.inserted_at >= key.observed_at,
        where: p.fleet_id == ^fleet_id,
        select: %{wallet: key.owner_wallet, at: v.inserted_at}
      )

    events = renewed |> union_all(^posted) |> union_all(^messaged) |> union_all(^started)

    from(event in subquery(union_all(events, ^voted)),
      group_by: event.wallet,
      select: {event.wallet, max(event.at)}
    )
    # Only each holder's latest time leaves the database, never what was said.
    |> Regents.Repo.all()
    |> Map.new(fn {wallet, at} -> {wallet, DateTime.from_naive!(at, "Etc/UTC")} end)
  end

  @doc """
  The holder of each of `token_ids` today and the Key they write as, as
  `%{token_id => %{holder: holder, face: token_id, owner: wallet, owned:
  count}}`; a key nobody holds yet is left out. A holder is a Regent account
  with every address it links, or an address no account links, as `holders/4`
  counts them. `face` is the key they chose to write as while their wallets
  hold it (`Regents.Keyfleet.Keys.PostingKey`), else the highest-ranked key their
  wallets hold, as `identity/2` picks it; `owner` is their main address and
  `owned` how many of the fleet's keys their addresses hold together. It is
  the holder's: an agent they put on another of their keys
  (`Regents.Keyfleet.Keys.AgentKey`) writes as that key, and the holder's face stays.
  """
  def faces(_fleet_id, []), do: %{}

  def faces(fleet_id, token_ids) do
    owners =
      Regents.Keyfleet.Keys.KeyAttachment
      |> Ash.Query.for_read(:owned_in_fleet, %{fleet_id: fleet_id, token_ids: token_ids})
      |> Ash.Query.select([:token_id, :owner_wallet])
      |> Ash.read!()
      |> Map.new(&{&1.token_id, &1.owner_wallet})

    linked = linked_to(owners |> Map.values() |> Enum.uniq())
    account_ids = linked |> Map.values() |> Enum.uniq()
    wallets = account_wallets(account_ids)
    # Every address of those accounts, not only the ones holding `token_ids`.
    holders =
      for {account_id, own} <- wallets, wallet <- own, into: linked, do: {wallet, account_id}

    holder = fn wallet -> holders[wallet] || wallet end
    addresses = fn holder -> Map.get(wallets, holder, [holder]) end

    held =
      fleet_id
      |> keys_held_in_fleet!(
        owners
        |> Map.values()
        |> Enum.map(holder)
        |> Enum.uniq()
        |> Enum.flat_map(addresses)
      )
      |> Enum.group_by(&holder.(&1.owner_wallet), & &1.token_id)

    chosen = chosen_keys(fleet_id, account_ids)
    main = main_addresses(account_ids)

    Map.new(owners, fn {token_id, wallet} ->
      holder = holder.(wallet)
      keys = Map.get(held, holder, [token_id])

      {token_id,
       %{
         holder: holder,
         face: if(chosen[holder] in keys, do: chosen[holder], else: Enum.min(keys)),
         owner: main[holder] || wallet,
         owned: length(keys)
       }}
    end)
  end

  # The account linking each of `wallets`, as `holders/4` counts them; an
  # address no account links is left out.
  defp linked_to(wallets) do
    from(linked in subquery(linked_wallets()),
      where: linked.wallet in ^wallets,
      select: {linked.wallet, linked.account_id}
    )
    # Every address a Regent account links is public, as in holders/4.
    |> Regents.Repo.all()
    |> Map.new()
  end

  # Every address each of `account_ids` links, as `holders/4` counts them.
  defp account_wallets([]), do: %{}

  defp account_wallets(account_ids) do
    from(linked in subquery(linked_wallets()),
      where: linked.account_id in ^account_ids,
      select: {linked.account_id, linked.wallet}
    )
    # Every address a Regent account links is public, as in holders/4.
    |> Regents.Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # The key each of `account_ids` chose to write as in the fleet. What a
  # person writes shows it beside their words, so it is no secret.
  defp chosen_keys(_fleet_id, []), do: %{}

  defp chosen_keys(fleet_id, account_ids) do
    fleet_id
    |> posting_keys_of_accounts!(account_ids, actor: %Regents.Account.Actors.System{})
    |> Map.new(&{&1.human_account_id, &1.token_id})
  end

  # The main address of each of `account_ids`, as the Member List names them.
  defp main_addresses([]), do: %{}

  defp main_addresses(account_ids) do
    account_ids
    |> Regents.Account.Accounts.accounts_by_ids!(actor: %Regents.Account.Actors.System{})
    |> Map.new(&{&1.id, &1.wallet_address && String.downcase(&1.wallet_address)})
  end

  # The fleet's keys with their owners today, as `:owned_in_fleet` reads them.
  defp owned(fleet_id) do
    {:ok, query} =
      Regents.Keyfleet.Keys.KeyAttachment
      |> Ash.Query.for_read(:owned_in_fleet, %{fleet_id: fleet_id})
      |> Ash.Query.data_layer_query()

    query
  end

  defp count_owners(fleet_id, token_ids) do
    Regents.Keyfleet.Keys.KeyAttachment
    |> Ash.Query.for_read(:owned_in_fleet, %{fleet_id: fleet_id, token_ids: token_ids})
    |> Ash.aggregate({:owners, :count, field: :owner_wallet, uniq?: true})
    |> case do
      {:ok, %{owners: owners}} -> {:ok, owners}
      {:error, failure} -> {:error, failure}
    end
  end

  # The keys that posted, sent a direct message, or started or voted in a
  # poll in the fleet since `since`, read across the four tables at once
  # since no one resource reads them all.
  defp acted_keys(fleet_id, since) do
    since = DateTime.to_naive(since)

    posted =
      from(m in "messages",
        prefix: ^Regents.Keyfleet.schema(),
        where: m.fleet_id == ^fleet_id and m.inserted_at >= ^since and not is_nil(m.as_key),
        select: m.as_key
      )

    messaged =
      from(d in "dm_messages",
        prefix: ^Regents.Keyfleet.schema(),
        where: d.fleet_id == ^fleet_id and d.inserted_at >= ^since,
        select: d.from_token_id
      )

    started =
      from(p in "polls",
        prefix: ^Regents.Keyfleet.schema(),
        where: p.fleet_id == ^fleet_id and p.inserted_at >= ^since,
        select: p.started_by_key
      )

    voted =
      from(v in "poll_votes",
        prefix: ^Regents.Keyfleet.schema(),
        join: p in "polls",
        prefix: ^Regents.Keyfleet.schema(),
        on: p.id == v.poll_id,
        where: p.fleet_id == ^fleet_id and v.inserted_at >= ^since,
        select: v.token_id
      )

    posted
    |> union(^messaged)
    |> union(^started)
    |> union(^voted)
    |> Regents.Repo.all()
  end

  @doc """
  The fleet's keys a person's wallets hold: the lowest `shown` of them by
  number, the lowest of all (who the person is in the fleet unless they chose
  another Key to write as, `identity/2`) and how many they hold, as `%{first: token_id, token_ids: token_ids, count: count}`,
  or `nil` for someone holding none. Reads `shown` keys and a count, however
  many the person holds.
  """
  def held_summary(%Human{wallet_addresses: [_ | _] = wallets} = actor, fleet_id, shown) do
    held =
      Ash.Query.for_read(
        Regents.Keyfleet.Keys.KeyAttachment,
        :held_in_fleet,
        %{fleet_id: fleet_id, owner_wallets: wallets},
        actor: actor
      )

    case held |> Ash.Query.limit(shown) |> Ash.read!() |> Enum.map(& &1.token_id) do
      [] -> nil
      [first | _] = token_ids -> %{first: first, token_ids: token_ids, count: Ash.count!(held)}
    end
  end

  def held_summary(_actor, _fleet_id, _shown), do: nil

  defp agent_key(key, wallet, for_person?),
    do: %{
      token_id: key.token_id,
      ownership_epoch: key.ownership_epoch,
      wallet: wallet,
      for_person: for_person?
    }

  defp person_keys(%Human{wallet_addresses: [_ | _] = wallets} = person, fleet_id, opts) do
    with {:ok, keys} <- keys_held_in_fleet(fleet_id, wallets, [actor: person] ++ opts),
         do: {:ok, Enum.map(keys, &agent_key(&1, &1.owner_wallet, true))}
  end

  defp person_keys(_missing, _fleet_id, _opts), do: {:ok, []}

  defp active_shard_in(fleet_id, wallet, actor),
    do: Enum.find(active_shards_held_by!(wallet, actor: actor), &(&1.fleet_id == fleet_id))
end
