defmodule Regents.AgentAccount do
  @moduledoc """
  How an agent's check-in names the account it is paired with: as the
  person's own Account page names it.
  """

  alias Regents.Accounts
  alias Regents.Actors.System

  # Nil when this site has no account for the person; the check-in is then refused.
  @spec account(String.t()) :: %{display_name: String.t() | nil, ens_name: String.t() | nil} | nil
  def account(privy_user_id) do
    case Accounts.get_by_privy_did(privy_user_id, actor: %System{}, load: [:ens_name]) do
      {:ok, %{} = account} -> %{display_name: account.display_name, ens_name: account.ens_name}
      {:ok, nil} -> nil
    end
  end
end
