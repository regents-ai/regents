defmodule RegentPoints.Accounts do
  @moduledoc "Host callbacks for canonical, server-verified account and agent information. Never accept browser attribution."
  @callback human(pos_integer()) :: %{
              wallet_address: String.t() | nil,
              wallet_addresses: [String.t()]
            }
  @callback agent_names(pos_integer(), [String.t()]) ::
              {:ok, %{String.t() => String.t()}} | {:error, term()}

  @doc """
  How each account shows to other people, for the leaderboard: `name` is the name
  the site shows for it, or `nil` when it shows the account's `wallet` instead,
  labelled with `ens_name` when the wallet has one; `squares` and `picture` are
  image addresses. Any of them may be `nil`.
  """
  @callback people([pos_integer()]) ::
              {:ok,
               %{
                 pos_integer() => %{
                   name: String.t() | nil,
                   wallet: String.t() | nil,
                   ens_name: String.t() | nil,
                   squares: String.t() | nil,
                   picture: String.t() | nil
                 }
               }}
              | {:error, term()}
end
