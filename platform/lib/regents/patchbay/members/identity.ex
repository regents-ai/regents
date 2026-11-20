defmodule Regents.Patchbay.Members.Identity do
  @moduledoc """
  How a person shows on regents.sh, for a member holding their Privy id: the
  name they set on their Regents account, the ENS name their wallet publishes
  and that name's picture (`Regents.Account.PublicIdentity.people_by_privy_ids/1`),
  as `%{display_name, ens_name, ens_avatar_url}`, each nil when the account
  shows none. Nil for a wallet author, which has no person and is never asked
  for, and for a Privy id with no account here.
  """

  use Ash.Resource.Calculation

  alias Regents.Account.PublicIdentity

  # The most Privy ids one read of the accounts takes.
  @per_read 100

  @impl true
  def load(_query, _opts, _context), do: [:privy_user_id]

  @impl true
  def calculate(members, _opts, _context) do
    with {:ok, people} <- people(members) do
      {:ok, Enum.map(members, &shown(people[&1.privy_user_id]))}
    end
  end

  defp people(members) do
    members
    |> Enum.map(& &1.privy_user_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.chunk_every(@per_read)
    |> Enum.reduce_while({:ok, %{}}, fn privy_ids, {:ok, people} ->
      case PublicIdentity.people_by_privy_ids(privy_ids) do
        {:ok, found} -> {:cont, {:ok, Map.merge(people, found)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp shown(nil), do: nil
  defp shown(person), do: Map.take(person, [:display_name, :ens_name, :ens_avatar_url])
end
