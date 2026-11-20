defmodule Regents.Account.Actors.Human do
  @moduledoc "A signed-in person: the account's id and every wallet it links, lowercased."
  @enforce_keys [:human_account_id]
  defstruct [:human_account_id, wallet_addresses: [], role: :human]

  @type t :: %__MODULE__{
          human_account_id: integer(),
          wallet_addresses: [String.t()],
          role: :human
        }

  @doc "The person an account row is: its id, its main wallet and every linked wallet."
  @spec for_account(%{id: integer(), wallet_address: term(), wallet_addresses: term()}) :: t()
  def for_account(account),
    do: %__MODULE__{human_account_id: account.id, wallet_addresses: wallets(account)}

  defp wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end
end
