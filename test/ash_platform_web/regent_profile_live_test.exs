defmodule AshPlatformWeb.RegentProfileLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation}
  alias AshPlatform.Actors.{Human, System}

  test "a public Regent profile shows only admitted public fields", %{conn: conn} do
    account =
      Accounts.register_verified!(
        "did:privy:public-profile",
        "0x1111111111111111111111111111111111111111",
        ["0x1111111111111111111111111111111111111111"],
        actor: %System{}
      )

    regent =
      Formation.form_regent!("public-atlas", "Public Atlas",
        actor: %Human{human_account_id: account.id}
      )

    Formation.update_profile!(regent, "Public Atlas", "Research and synthesis.",
      actor: %Human{human_account_id: account.id}
    )

    {:ok, view, _html} = live(conn, "/regents/public-atlas")
    html = render_async(view)

    assert has_element?(view, "#public-regent-profile")
    assert html =~ "Public Atlas"
    assert html =~ "Research and synthesis."
    assert html =~ account.wallet_address
    refute html =~ account.privy_user_id
    refute html =~ "Billing"
  end

  test "an unknown Regent slug has an honest empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/regents/not-here")
    html = render_async(view)

    assert html =~ "Regent not found"
    assert html =~ "This public Regent profile does not exist."
  end

  test "the public projection exposes the selected profile, verified wallet, and coarse Cloud state only",
       %{conn: conn} do
    wallet = "0x2222222222222222222222222222222222222222"

    account =
      Accounts.register_verified!(
        "did:privy:public-projection",
        wallet,
        [wallet],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("projection-atlas", "Projection Atlas", actor: actor)

    Formation.update_profile!(
      regent,
      "Projection Atlas",
      "A field-limited public profile.",
      %{avatar_url: "https://images.regents.sh/projection-atlas.png"},
      actor: actor
    )

    runtime = Formation.provision_cloud_runtime!(actor: actor)

    {:ok, view, _html} = live(conn, "/regents/projection-atlas")
    html = render_async(view)

    assert has_element?(
             view,
             ~s(img[src="https://images.regents.sh/projection-atlas.png"])
           )

    assert has_element?(view, ~s(code[title="#{wallet}"]), "0x2222…2222")
    assert html =~ "Hermes not connected"
    refute html =~ account.privy_user_id
    refute html =~ runtime.provider_sprite_id
    refute html =~ runtime.url
  end
end
