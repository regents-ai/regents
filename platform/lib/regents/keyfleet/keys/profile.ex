defmodule Regents.Keyfleet.Keys.Profile do
  @moduledoc """
  Everything one key's profile shows, as a plain map: the key itself, the
  wallet holding it and the Key it writes as, its thread and what it has said
  in the fleet's rooms.

  Every figure is read with a fixed number of indexed reads, so opening a key
  costs the same however large the fleet is and however many keys its holder
  has. Nothing here writes.

  A key the fleet has not issued yet, the next one on sale, has only its
  number, level and price.
  """

  alias Regents.Account.Actors.{Human, System}
  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Fleet
  alias Regents.Keyfleet.Fleets.Presets
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.KeyAttachment
  alias Regents.Keyfleet.Keys.Metadata
  alias Regents.Keyfleet.Proposals.Vote
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Message
  alias Regents.Keyfleet.Rooms.WallRemoval
  alias Regents.Keyfleet.Traits

  # A holder's keys in the fleet are listed this many at a time.
  @listed 100
  # A thread opens on its latest posts.
  @thread_page 100

  @doc """
  Key `token_id` of the fleet as `viewer` sees it, `viewer` being the person
  signed in or `nil`. `issued?` is false for a key not yet sold. An issued
  key's `thread` holds every post, and `muted` the keys the viewer has muted,
  whose posts the page leaves out.
  """
  def read(fleet_id, token_id, viewer) do
    case Keys.current_key!(fleet_id, token_id) do
      nil -> unissued(fleet_id, token_id)
      current -> issued(fleet_id, token_id, current, viewer)
    end
  end

  @doc """
  Whether `wallet` holds, or has held, any of `token_ids` in the fleet: so
  whether a change to those keys moved one of its keys, to it or away from it.
  """
  def held_any?(fleet_id, wallet, token_ids) do
    KeyAttachment
    |> Ash.Query.for_read(:held_among, %{
      fleet_id: fleet_id,
      owner_wallet: wallet,
      token_ids: token_ids
    })
    |> Ash.exists?()
  end

  @doc """
  Who may write in the key's thread: the same people as in the fleet's rooms,
  while the fleet's key ownership is fresh. `viewer` is the person signed in,
  or `nil`.
  """
  def composer(nil, _fleet_id), do: :sign_in

  def composer(%Human{} = viewer, fleet_id) do
    cond do
      Keys.identity(viewer, fleet_id) == nil -> :no_key
      not Chain.fresh?(fleet_id) -> :refreshing
      true -> :write
    end
  end

  @doc """
  What changes when the key, or a key its holder holds, has written or been
  written to, or a post has come off its wall: how many posts its wall shows
  (`messages`) and the place of the last one written to it (`wall_head`), its
  posts in the rooms anyone reads, and its holder's.
  Read as nobody, so the fleet's other rooms, which only its keys read, never
  show here.
  """
  def activity(fleet_id, token_id, holder) do
    thread = Rooms.get_key_thread!(fleet_id, token_id)
    wall_head = if(thread, do: thread.head_seq, else: 0)
    removed = count(WallRemoval, :of_wall, %{fleet_id: fleet_id, token_id: token_id})

    %{
      wall_head: wall_head,
      messages: wall_head - removed,
      posts: count(Message, :room_posts_as_key, %{fleet_id: fleet_id, token_id: token_id}),
      recent_posts: Rooms.posts_as_key!(fleet_id, token_id),
      holder_posts: count(Message, :room_posts_by_wallet, %{fleet_id: fleet_id, wallet: holder})
    }
  end

  @doc "The posts in the key's thread after place `after_seq`, oldest first."
  def thread_after(fleet_id, token_id, after_seq) do
    Rooms.read_key_thread!(fleet_id, token_id, %{after_seq: after_seq, limit: @thread_page})
  end

  @doc "The latest posts in the key's thread up to place `last_seq`, oldest first."
  def latest_thread(fleet_id, token_id, last_seq),
    do: thread_after(fleet_id, token_id, max(last_seq - @thread_page, 0))

  @doc """
  The votes the key has been used in, and the votes its holder has cast in
  the fleet with all their keys and on how many proposals.
  """
  def votes(fleet_id, token_id, holder) do
    by_holder =
      Vote
      |> Ash.Query.for_read(:by_voter, %{fleet_id: fleet_id, voter: holder})
      |> Ash.aggregate!([
        {:votes, :sum, field: :key_count},
        {:proposals, :count, field: :proposal_id, uniq?: true}
      ])

    %{
      votes_cast: count(Vote, :with_key, %{fleet_id: fleet_id, token_id: token_id}),
      holder_votes: by_holder.votes || 0,
      holder_proposals: by_holder.proposals
    }
  end

  defp unissued(fleet_id, token_id) do
    %{
      fleet_id: fleet_id,
      token_id: token_id,
      issued?: false,
      image: Metadata.pass(),
      level: level(fleet_id, token_id),
      issue_price: Presets.issue_price(fleet_id, token_id)
    }
  end

  # `current` is the record of the holder receiving the key.
  defp issued(fleet_id, token_id, current, viewer) do
    fleet = Fleets.get_fleet!(fleet_id)
    holder = current.owner_wallet
    activity = activity(fleet_id, token_id, holder)
    thread = latest_thread(fleet_id, token_id, activity.wall_head)
    traits = traits(fleet, token_id)

    held =
      Keys.keys_held_in_fleet!(fleet_id, [holder], query: [limit: @listed])
      |> Enum.map(& &1.token_id)

    %{
      fleet_id: fleet_id,
      token_id: token_id,
      issued?: true,
      image: Metadata.image(fleet, token_id),
      level: level(fleet_id, token_id),
      issue_price: Presets.issue_price(fleet_id, token_id),
      traits: traits,
      draw_ended?: is_nil(traits) and Keys.get_reveal_expiry!(fleet_id, token_id) != nil,
      held_since: current.observed_at,
      holder: holder,
      posts_as: posts_as(fleet, token_id),
      opensea: opensea(fleet, token_id),
      yours?: holder in wallets(viewer),
      held_for_pass?: Presets.given?(fleet_id) and holder == fleet.club_claims_address,
      changed_hands:
        count(KeyAttachment, :history, %{fleet_id: fleet_id, token_id: token_id}) - 1,
      shards: shards(fleet_id, token_id),
      thread: thread,
      last_seq: last_seq(thread, 0),
      muted: Rooms.muted_keys!(fleet_id, viewer),
      holder_keys: held,
      holder_key_count:
        count(KeyAttachment, :held_in_fleet, %{fleet_id: fleet_id, owner_wallets: [holder]}),
      holder_keys_everywhere: count(KeyAttachment, :held_everywhere, %{owner_wallets: [holder]}),
      composer: composer(viewer, fleet_id)
    }
    |> Map.merge(activity)
    |> Map.merge(votes(fleet_id, token_id, holder))
  end

  @doc "The place of the last of `posts`, or `shown` when there are none."
  def last_seq([], shown), do: shown
  def last_seq(posts, _shown), do: List.last(posts).seq

  # The Key its holder writes as in the fleet, as everything they write shows
  # it (`Regents.Keyfleet.Keys.faces/2`), with its small card.
  defp posts_as(fleet, token_id) do
    %{^token_id => %{face: face}} = Keys.faces(fleet.id, [token_id])
    %{token_id: face, image: Metadata.small_cards(fleet, [face])[face]}
  end

  # The Key's own page on OpenSea, by its token id on Base.
  defp opensea(fleet, token_id),
    do:
      "https://opensea.io/item/base/#{fleet.keys_address}/#{Fleet.onchain_token_id(fleet, token_id)}"

  defp level(fleet_id, token_id),
    do: if(Presets.levelled?(fleet_id), do: Presets.fibonacci_level_of(token_id))

  # Each trait the key's card has, in its fleet's order, with the share of
  # keys that draw it; `nil` while the key is still revealing, or for good
  # once the wait for its draw was ended (`draw_ended?`).
  defp traits(fleet, token_id) do
    case Keys.card_seed(fleet, token_id) do
      nil ->
        nil

      seed ->
        table = Traits.table!(fleet.trait_table_hash)
        weights = Map.new(table, &{&1.name, {Map.new(&1.values), &1.total}})

        table
        |> Traits.draw(seed)
        |> Enum.map(fn {trait, value} ->
          {values, total} = weights[trait]
          %{trait: trait, value: value, share: values[value] / total}
        end)
    end
  end

  @doc """
  The key's active shards, soonest to run out first and a hundred at most:
  each wallet, when its shard runs out, and the agent behind it with its saved
  registry page and World ID mark and the other agents here the same person
  stands behind, or nil when the wallet has not signed in as an agent yet.
  What each agent's check-ins say is shared by every page
  (`Regents.Keyfleet.Agents.Here`).
  """
  def shards(fleet_id, token_id) do
    shards =
      Keys.active_shards_of_keys!(fleet_id, [token_id],
        load: [:agent_profile],
        query: [limit: @listed]
      )

    listings =
      for(%{agent_profile: %{id: id}} <- shards, do: id)
      |> Agents.listings!(actor: %System{})
      |> Map.new(&{&1.id, &1})

    people =
      for(%{human_id: "0x" <> _number = human_id} <- Map.values(listings), do: human_id)
      |> Enum.uniq()
      |> Agents.agents_of_people!(actor: %System{})
      |> Enum.group_by(& &1.human_id)

    Enum.map(shards, fn shard ->
      %{
        wallet: shard.wallet,
        expires_at: shard.expires_at,
        agent:
          shard.agent_profile &&
            agent(shard.agent_profile, listings[shard.agent_profile.id], people)
      }
    end)
  end

  defp agent(agent, listing, people) do
    %{
      name: agent.name,
      registry_url: listing.registry_url,
      backing: RegentAgents.HumanBacking.describe(listing),
      same_person:
        for(other <- Map.get(people, listing.human_id, []), other.id != agent.id, do: other.name),
      avatar_src: agent.avatar_src,
      harness: agent.declared_harness,
      status: agent.current_status,
      status_updated_at: agent.status_updated_at
    }
  end

  defp wallets(%Human{wallet_addresses: wallets}), do: wallets
  defp wallets(nil), do: []

  defp count(resource, action, arguments),
    do: resource |> Ash.Query.for_read(action, arguments) |> Ash.count!()
end
