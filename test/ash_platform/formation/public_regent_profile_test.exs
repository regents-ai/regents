defmodule AshPlatform.Formation.PublicRegentProfileTest do
  use AshPlatformWeb.ConnCase, async: true

  alias AshPlatform.{Accounts, Formation}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Formation.PublicRegentProfile

  @wallet "0x4444444444444444444444444444444444444444"

  test "the public interface returns only approved profile fields" do
    account =
      Accounts.register_verified!(
        "did:privy:profile-projection-domain",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("domain-atlas", "Domain Atlas", actor: actor)

    Formation.update_profile!(
      regent,
      "Domain Atlas",
      "Public summary.",
      %{avatar_url: "/images/regents/domain-atlas.png"},
      actor: actor
    )

    profile = Formation.get_public_regent_profile!("domain-atlas")

    assert %PublicRegentProfile{
             slug: "domain-atlas",
             display_name: "Domain Atlas",
             summary: "Public summary.",
             avatar_url: "/images/regents/domain-atlas.png",
             verified_wallet_address: @wallet,
             cloud_connected?: false
           } = profile

    refute Map.has_key?(profile, :human_account_id)
    refute Map.has_key?(profile, :privy_user_id)
    refute Map.has_key?(profile, :provider_sprite_id)
    refute Map.has_key?(profile, :url)
  end

  test "the private source reads deny callers without the system actor" do
    account =
      Accounts.register_verified!(
        "did:privy:profile-projection-source",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    regent =
      Formation.form_regent!("source-atlas", "Source Atlas",
        actor: %Human{human_account_id: account.id}
      )

    assert {:error, %Ash.Error.Forbidden{}} = Accounts.get_public_profile_source(account.id)

    assert {:error, %Ash.Error.Forbidden{}} =
             Formation.get_public_cloud_profile_source(regent.id)
  end

  test "the public avatar rejects unsafe URL schemes" do
    account =
      Accounts.register_verified!(
        "did:privy:profile-projection-avatar",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("avatar-atlas", "Avatar Atlas", actor: actor)

    for unsafe_url <- [
          "//attacker.example/avatar.png",
          "https:///missing-host.png",
          "https://user@attacker.example/avatar.png",
          "javascript:alert(1)"
        ] do
      assert {:error, %Ash.Error.Invalid{}} =
               Formation.update_profile(
                 regent,
                 "Avatar Atlas",
                 nil,
                 %{avatar_url: unsafe_url},
                 actor: actor
               )
    end
  end
end
