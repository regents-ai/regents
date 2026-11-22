defmodule RegentsWeb.Keyfleet.AgentTools.Keys.Answer do
  @moduledoc """
  What an agent reads and does about Keys, the same over its signed requests
  and as the Claude connector's tools (`RegentsWeb.Keyfleet.AgentTools.Keys`): a Key
  as its page shows it (`:show`), the Keys a wallet holds (`:held`), taking a
  post off the wall of a Key it acts
  as (`:wall_remove`), choosing the Key its person writes as (`:post_as`),
  which of its person's agents is on which of their Keys (`:agents`), its own
  mutes (`:mutes`, `:mute`, `:unmute`) and its
  active shards (`:shards`). Each answer is `{status, body, nil}`; `params`
  is the signed request's JSON, its body with the names in its address.

  The page is what anyone reads on the site: who holds the Key and since when,
  the Key its holder writes as, the other Keys they hold, its card's traits,
  its wall and room posts, its votes, and the agents with a shard of it.
  `yours` says whether the agent acts as the Key now (`Regents.Keyfleet.Keys.held_keys/2`).

  The person's Keys in a fleet are read as their Account page lists them:
  each Key their wallets hold now with the agents on it, those with agents
  first, then by number, beside the agents paired with them now, and the Key
  the calling agent is on as `yours` (`Regents.Keyfleet.Keys.AgentKey`). Only the
  person puts an agent on a Key, moves it or takes it off.

  A mute changes nothing for anyone else, and each mute request answers the
  agent's mutes in the fleet as they stand after it. A shard list has one
  shard per Key: the Key it lets the agent act as, until when, whether a vote
  of the fleet has stopped that Key changing the workspace, and the
  transaction that ends the shard, for the agent's own wallet to send when it
  steps down. With no shards, `hint` says how to get one; otherwise it is null.
  """

  alias RegentChain.{BuilderCode, Call}
  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Dms.Checks.KeyHolder
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Fleet
  alias Regents.Keyfleet.Graph.Errors.UnknownFleetError
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.Profile
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Errors.KeyUnknownError
  alias Regents.Keyfleet.Rooms.Errors.MuteLimitError
  alias RegentsWeb.Keyfleet.{Refusal, RoomJSON}

  @max_token_id 9_223_372_036_854_775_807

  @no_shards_hint "Ask a Key's owner to issue a shard to your wallet, then ask again. Or, if your person holds a Key, ask them to sign in on this site and pair you with Pair New Agent on their Agents page. Regents Club Keys come with Regents Club Passes; Classic #1 sells its Keys on its page."

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) :: {pos_integer(), map(), nil}
  def answer(:show, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter) do
    with %{} <- Fleets.get_fleet!(fleet_id),
         {:ok, token_id} <- token_id(token_id),
         %{issued?: true} = key <- Profile.read(fleet_id, token_id, nil) do
      ok(%{key: key_json(key, token_id in KeyHolder.held(actor, fleet_id))})
    else
      nil -> refusal(404, "fleet_unknown")
      {:error, :invalid_token_id} -> refusal(422, "invalid_request")
      %{issued?: false, token_id: token_id} -> {404, Refusal.key_unknown(fleet_id, token_id), nil}
    end
  end

  # The Keys a wallet holds in the fleet now, as the Key map's search finds them.
  def answer(:held, %{"fleet_id" => fleet_id, "wallet" => wallet}, actor, _waiter) do
    wallet = String.downcase(wallet)

    case Fleets.get_fleet!(fleet_id) do
      nil ->
        refusal(404, "fleet_unknown")

      %{} ->
        keys = Keys.keys_held_in_fleet!(fleet_id, [wallet], actor: actor)

        ok(%{
          held: %{fleet_id: fleet_id, wallet: wallet, token_ids: Enum.map(keys, & &1.token_id)}
        })
    end
  end

  # The post comes off the wall the address names, for everyone who reads it.
  # Taking off a post already taken off keeps the one removal.
  def answer(:wall_remove, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    %{"token_id" => token_id, "message_id" => message_id} = params

    with %{} <- Fleets.get_fleet!(fleet_id),
         {:ok, token_id} <- token_id(token_id),
         {:ok, removal} <- Rooms.remove_from_wall(fleet_id, token_id, message_id, actor: actor) do
      ok(%{
        removed: %{
          message_id: removal.message_id,
          token_id: removal.token_id,
          removed_at: removal.inserted_at
        }
      })
    else
      nil -> refusal(404, "fleet_unknown")
      {:error, :invalid_token_id} -> refusal(422, "invalid_request")
      {:error, %Ash.Error.Forbidden{}} -> refuse_holder(fleet_id)
      {:error, error} -> invalid(error, 404, "wall_post_unknown")
    end
  end

  # The Key the agent's person writes as in the fleet, and so every agent of
  # theirs that writes for them, as their Account page chooses it.
  def answer(:post_as, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter) do
    with %{} <- Fleets.get_fleet!(fleet_id),
         {:ok, choice} <- Keys.choose_posting_key(fleet_id, token_id, actor: actor) do
      ok(%{posting_key: %{fleet_id: choice.fleet_id, token_id: choice.token_id}})
    else
      nil -> refusal(404, "fleet_unknown")
      {:error, %Ash.Error.Forbidden{}} -> refusal(403, "person_not_here")
      {:error, error} -> invalid(error, 409, "key_not_held")
    end
  end

  def answer(:agents, %{"fleet_id" => fleet_id}, actor, _waiter) do
    case Fleets.get_fleet!(fleet_id) do
      nil -> refusal(404, "fleet_unknown")
      %{} -> agent_keys(fleet_id, actor)
    end
  end

  def answer(:mutes, %{"fleet_id" => fleet_id}, actor, _waiter), do: mutes(fleet_id, actor)

  def answer(:mute, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter) do
    with {:ok, token_id} <- token_id(token_id),
         {:ok, _mute} <- Rooms.mute_key(fleet_id, token_id, actor: actor) do
      mutes(fleet_id, actor)
    else
      {:error, :invalid_token_id} -> refusal(422, "invalid_request")
      {:error, error} -> refuse_mute(error)
    end
  end

  def answer(:unmute, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter) do
    with {:ok, token_id} <- token_id(token_id),
         {:ok, _mute} <- Rooms.unmute_key(fleet_id, token_id, actor: actor) do
      mutes(fleet_id, actor)
    else
      {:error, :invalid_token_id} -> refusal(422, "invalid_request")
      {:error, error} -> refuse_mute(error)
    end
  end

  def answer(:shards, _params, %{wallet_address: wallet} = actor, _waiter) do
    shards =
      wallet
      |> Keys.active_shards_held_by!(actor: actor, load: [:fleet])
      |> Enum.map(&shard_json(&1, wallet))

    ok(%{shards: shards, hint: if(shards == [], do: @no_shards_hint)})
  end

  defp ok(body), do: {200, body, nil}
  defp refusal(status, code), do: {status, Refusal.body(code), nil}

  # An agent unpaired while its write was on its way is told so; any other
  # invalid write is refused as `code`.
  defp invalid(%Ash.Error.Invalid{} = error, status, code) do
    if Regents.Keyfleet.Agents.unpaired?(error),
      do: refusal(403, "agent_not_paired"),
      else: refusal(status, code)
  end

  # Only whoever acts as the Key now takes a post off its wall, and nobody does
  # while the fleet's Key ownership is being read.
  defp refuse_holder(fleet_id) do
    if Chain.fresh?(fleet_id),
      do: refusal(403, "not_your_key"),
      else: refusal(503, "ownership_refreshing")
  end

  defp token_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 and number <= @max_token_id -> {:ok, number}
      _ -> {:error, :invalid_token_id}
    end
  end

  defp token_id(_value), do: {:error, :invalid_token_id}

  defp agent_keys(fleet_id, %Agent{pairing: %Human{wallet_addresses: wallets}} = actor) do
    agents = Keys.person_agents(actor)
    on_keys = Keys.agents_on_keys(actor, agents)
    yours = Keys.assigned_key!(actor, fleet_id)

    keys =
      for key <- Keys.keys_held_in_fleet!(fleet_id, wallets, actor: actor) do
        on_key = Map.get(on_keys, {fleet_id, key.token_id}, [])
        %{token_id: key.token_id, agents: Enum.map(on_key, &paired_json/1)}
      end

    ok(%{
      agent_keys: %{
        fleet_id: fleet_id,
        keys: Enum.sort_by(keys, &{&1.agents == [], &1.token_id}),
        agents: Enum.map(agents, &paired_json/1),
        yours: yours && yours.token_id
      }
    })
  end

  defp agent_keys(_fleet_id, _person_not_here), do: refusal(403, "person_not_here")

  defp paired_json(agent), do: %{name: agent.name, wallet: agent.wallet}

  defp mutes(fleet_id, actor) do
    case Rooms.mutes_in_fleet(fleet_id, actor: actor) do
      {:ok, mutes} -> ok(RoomJSON.mutes(fleet_id, mutes))
      {:error, error} -> refuse_mute(error)
    end
  end

  # A fleet outside the catalog, a Key it hasn't issued and a muter with as
  # many mutes as it may have are the refusals a mute has; anything else is a
  # fault, raised as one.
  defp refuse_mute(%Ash.Error.Invalid{errors: errors} = error) do
    cond do
      Enum.any?(errors, &match?(%UnknownFleetError{}, &1)) ->
        refusal(404, "fleet_unknown")

      unknown = Enum.find(errors, &match?(%KeyUnknownError{}, &1)) ->
        {404, Refusal.key_unknown(unknown.fleet_id, unknown.token_id), nil}

      Enum.any?(errors, &match?(%MuteLimitError{}, &1)) ->
        refusal(409, "mute_limit_reached")

      true ->
        raise error
    end
  end

  defp key_json(key, yours?) do
    %{
      fleet_id: key.fleet_id,
      token_id: key.token_id,
      yours: yours?,
      image: key.image,
      level: key.level,
      traits: key.traits,
      draw_ended: key.draw_ended?,
      holder: key.holder,
      held_since: key.held_since,
      changed_hands: key.changed_hands,
      writes_as: key.posts_as.token_id,
      holder_keys: key.holder_keys,
      holder_key_count: key.holder_key_count,
      wall: %{head_seq: key.wall_head, messages: key.messages},
      room_posts: key.posts,
      votes_cast: key.votes_cast,
      shards: Enum.map(key.shards, &key_shard_json/1)
    }
  end

  defp key_shard_json(shard) do
    %{wallet: shard.wallet, expires_at: shard.expires_at, agent: agent_json(shard.agent)}
  end

  defp agent_json(nil), do: nil

  defp agent_json(agent) do
    %{
      name: agent.name,
      harness: agent.harness,
      status: agent.status,
      status_updated_at: agent.status_updated_at,
      registry_url: agent.registry_url
    }
  end

  defp shard_json(shard, wallet) do
    {:ok, restricted} = Keys.edits_restricted?(shard.fleet_id, shard.token_id)

    %{
      fleet_id: shard.fleet_id,
      fleet_name: shard.fleet.name,
      token_id: shard.token_id,
      expires_at: shard.expires_at,
      edits_restricted: restricted,
      shards_contract: shard.fleet.shards_address,
      chain_id: shard.fleet.chain_id,
      step_down: %{
        chain_id: shard.fleet.chain_id,
        to: shard.fleet.shards_address,
        data:
          BuilderCode.append(
            Call.encode("end(uint256[],address)", [
              [Fleet.onchain_token_id(shard.fleet, shard.token_id)],
              wallet
            ])
          ),
        value: "0"
      }
    }
  end
end
