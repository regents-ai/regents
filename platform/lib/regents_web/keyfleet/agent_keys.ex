defmodule RegentsWeb.Keyfleet.AgentKeys do
  @moduledoc """
  The Keys a person's agents act for, as the Agents page shows them beside
  each agent (`RegentsWeb.Keyfleet.AgentsPanel`) and once an agent pairs
  (`RegentsWeb.Keyfleet.PairingBox`): the Key the person put each agent on in a fleet
  (`Regents.Keyfleet.Keys.AgentKey`) while it stands there
  (`Regents.Keyfleet.Keys.placed_on?/3`), and each Key the agent's wallet holds an
  active shard of, each linked to its page. For an
  agent with neither whose person holds a Key, the page links to Your Keys on
  the Account page (`assign_path/0`), where the person puts it on one. An
  agent with neither whose person holds no Key has nothing there.

  Shards and holders are public, as the chain records them; which agent is on
  which Key is read for the signed-in person alone. A failed read comes back
  as `{:error, failure}` (`RegentsWeb.Keyfleet.PageRead`), so the page says so rather
  than crashing.
  """

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Rules
  alias Regents.Keyfleet.Keys
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.PageRead

  @doc "Your Keys on the Account page, where the person puts an agent on a Key."
  def assign_path, do: "/account#account-keys"

  @doc """
  `{:ok, keys}`, where for each of `agents` (paired agents, each with its
  pairing `id` and `wallet`), by `id`, keys holds `{:keys, keys}`, each key
  `%{label, path}`; `:assign` when it is on no Key and the person holds one;
  or `nil`, read for the signed-in `account`. `{:error, failure}` when the
  read fails.
  """
  def read(_account, []), do: {:ok, %{}}

  def read(account, agents) do
    PageRead.run("account", fn ->
      actor = Human.for_account(account)

      on_keys =
        for {key, on_key} <- Keys.agents_on_keys(actor, agents),
            agent <- on_key,
            reduce: %{},
            do: (on_keys -> Map.update(on_keys, agent.id, [key], &[key | &1]))

      holds_key? = holds_key?(actor)

      Map.new(agents, fn agent ->
        {agent.id, keys(agent, Map.get(on_keys, agent.id, []), actor, holds_key?)}
      end)
    end)
  end

  defp keys(agent, assigned, actor, holds_key?) do
    sharded =
      for shard <- Keys.active_shards_held_by!(agent.wallet, actor: actor),
          do: {shard.fleet_id, shard.token_id}

    case Enum.uniq(Enum.sort(assigned) ++ sharded) do
      [] -> if holds_key?, do: :assign
      keys -> {:keys, Enum.map(keys, &key/1)}
    end
  end

  defp key({fleet_id, token_id}),
    do: %{
      label: "#{Fleets.name(fleet_id)} Key #{Rules.grouped(token_id)}",
      path: KeyLinks.page_path(fleet_id, token_id)
    }

  defp holds_key?(%Human{wallet_addresses: [_ | _] = wallets} = actor),
    do: Keys.keys_held_everywhere!(wallets, actor: actor) != []

  defp holds_key?(_actor), do: false
end
