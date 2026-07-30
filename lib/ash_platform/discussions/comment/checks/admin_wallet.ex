defmodule AshPlatform.Discussions.Comment.Checks.AdminWallet do
  use Ash.Policy.SimpleCheck

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.Human

  @impl true
  def describe(_opts), do: "actor controls a configured Regent admin wallet"

  @impl true
  def match?(actor, _context, _opts), do: admin?(actor)

  def admin?(%Human{human_account_id: id} = actor) when is_integer(id) do
    case Accounts.get_human_account(id, actor: actor) do
      {:ok, account} when not is_nil(account) ->
        account
        |> account_wallets()
        |> Enum.any?(&MapSet.member?(configured_wallets(), &1))

      _ ->
        false
    end
  end

  def admin?(_actor), do: false

  defp configured_wallets do
    :ash_platform
    |> Application.get_env(:admin_wallet_addresses, [])
    |> Enum.map(&normalize_wallet/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp account_wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.map(&normalize_wallet/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_wallet(wallet) when is_binary(wallet) do
    case wallet |> String.trim() |> String.downcase() do
      <<"0x", hex::binary-size(40)>> = normalized ->
        if String.match?(hex, ~r/\A[0-9a-f]{40}\z/), do: normalized

      _ ->
        nil
    end
  end

  defp normalize_wallet(_wallet), do: nil
end
