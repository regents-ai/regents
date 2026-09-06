defmodule AshPlatform.Names.VerifiedOwner do
  use Ash.Policy.SimpleCheck
  def describe(_opts), do: "fresh paired Privy evidence for this application's wallet owner"

  def match?(%RegentPrivy.Session{app_id: app, wallet_addresses: wallets} = actor, _, _) do
    expected = Application.get_env(:ash_platform, :privy, [])[:app_id]

    RegentIdentity.VerifiedActor.match?(actor, nil, []) and app == expected and
      is_list(wallets) and
      Enum.all?(wallets, &(is_binary(&1) and Regex.match?(~r/^0x[0-9a-f]{40}$/, &1)))
  end

  def match?(_, _, _), do: false
end
