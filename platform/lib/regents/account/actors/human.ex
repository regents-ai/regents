defmodule Regents.Account.Actors.Human do
  @moduledoc "A signed-in person: the account's id and every wallet it links, lowercased."

  alias Regents.Account.Accounts
  alias Regents.Account.Actors.System

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

  @doc """
  The person's Privy id, read from their account: `{:ok, privy_id}`, or `:error`
  when no account here has the person's id.
  """
  @spec privy_id(t()) :: {:ok, String.t()} | :error
  def privy_id(%__MODULE__{human_account_id: id}) do
    case Accounts.accounts_by_ids!([id], actor: %System{}) do
      [%{privy_user_id: privy_id}] -> {:ok, privy_id}
      [] -> :error
    end
  end

  defp wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end
end
