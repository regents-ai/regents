defmodule AshPlatform.PublicIdentityTest do
  use ExUnit.Case, async: true

  alias AshPlatform.PublicIdentity

  test "public labels resolve profile choice, Regent nameclaim, ENS, then abbreviated wallet" do
    identity = %{
      display_name: "Profile choice",
      regent_nameclaim: "atlas.regent.eth",
      ens_name: "atlas.eth",
      wallet_address: "0x111111111111111111111111111111111111a1b2"
    }

    assert PublicIdentity.label(identity) == "Profile choice"
    assert PublicIdentity.label(%{identity | display_name: " "}) == "atlas.regent.eth"

    assert PublicIdentity.label(%{identity | display_name: nil, regent_nameclaim: nil}) ==
             "atlas.eth"

    assert PublicIdentity.label(%{
             identity
             | display_name: nil,
               regent_nameclaim: nil,
               ens_name: nil
           }) == "0x1111…a1b2"
  end

  test "wallet avatars are local, deterministic, and address-specific" do
    first =
      PublicIdentity.avatar_src(%{
        wallet_address: "0x111111111111111111111111111111111111a1b2"
      })

    retry =
      PublicIdentity.avatar_src(%{
        wallet_address: "0x111111111111111111111111111111111111A1B2"
      })

    other =
      PublicIdentity.avatar_src(%{
        wallet_address: "0x222222222222222222222222222222222222a1b2"
      })

    assert first == retry
    assert first != other
    assert "data:image/svg+xml;base64," <> encoded = first
    assert Base.decode64!(encoded) =~ ~s(<svg xmlns="http://www.w3.org/2000/svg")
    refute first =~ "0x1111"
    assert PublicIdentity.avatar_src(%{wallet_address: nil}) == nil
  end

  test "an ENS picture is preferred, and a blank one leaves the generated picture" do
    wallet = %{wallet_address: "0x111111111111111111111111111111111111a1b2"}
    generated = PublicIdentity.avatar_src(wallet)

    assert PublicIdentity.avatar_src(
             Map.put(wallet, :ens_avatar_url, "https://avatars.regents.test/atlas.png")
           ) == "https://avatars.regents.test/atlas.png"

    assert PublicIdentity.avatar_src(Map.put(wallet, :ens_avatar_url, " ")) == generated
    assert PublicIdentity.avatar_src(Map.put(wallet, :ens_avatar_url, nil)) == generated
  end
end
