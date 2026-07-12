defmodule AshPlatform.AccessContextTest do
  use ExUnit.Case, async: true

  alias AshPlatform.AccessContext

  @wallet "0x1111111111111111111111111111111111111111"

  test "anonymous account control exposes only sign in" do
    assert %{kind: :sign_in, label: "Sign In", profile_path: nil, settings_path: nil} =
             AccessContext.account_control(AccessContext.anonymous())
  end

  test "a signed human without a Regent has settings but no profile target" do
    account = %{wallet_address: @wallet, display_name: "Account label"}

    assert %{
             kind: :signed_in,
             label: "Account label",
             profile_path: nil,
             settings_path: "/settings"
           } =
             AccessContext.account_control(AccessContext.human(account))
  end

  test "only a server-supplied Regent creates the canonical profile target" do
    account = %{wallet_address: @wallet, display_name: "Human account label"}
    regent = %{slug: "ada", display_name: "Ada Regent"}

    assert %{
             kind: :signed_in,
             label: "Ada Regent",
             profile_path: "/regents/ada",
             settings_path: "/settings",
             avatar_data_uri: "data:image/svg+xml;base64," <> _
           } = AccessContext.account_control(AccessContext.human(account), regent)
  end
end
