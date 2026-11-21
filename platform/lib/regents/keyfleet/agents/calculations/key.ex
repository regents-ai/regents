defmodule Regents.Keyfleet.Agents.Calculations.Key do
  @moduledoc """
  The Key each agent a read lists acts as in a fleet, by the rule
  `Regents.Keyfleet.Keys.identity/2` follows: the lowest-numbered Key its own wallet
  holds, else the Key its person put it on, read for every listed agent at
  once by `Regents.Keyfleet.Keys.assigned_keys/3`, else its active shard's Key, else
  the Key its person writes as.
  """
  use Ash.Resource.Calculation

  alias Regents.Keyfleet.Keys

  @impl true
  def load(_query, _opts, %{arguments: %{fleet_id: fleet_id}}),
    do: [
      :wallet_address,
      held_key: %{fleet_ids: [fleet_id]},
      shard_key: %{fleet_id: fleet_id},
      paired_key: %{fleet_ids: [fleet_id]}
    ]

  @impl true
  def calculate(profiles, _opts, %{arguments: %{fleet_id: fleet_id}}) do
    with {:ok, assigned} <- Keys.assigned_keys(fleet_id, Enum.map(profiles, & &1.wallet_address)) do
      {:ok,
       Enum.map(profiles, fn profile ->
         profile.held_key || token_id(assigned[profile.wallet_address]) || profile.shard_key ||
           profile.paired_key
       end)}
    end
  end

  defp token_id(nil), do: nil
  defp token_id(key), do: key.token_id
end
