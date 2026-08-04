defmodule AshPlatformWeb.FormationLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation}
  alias AshPlatform.Actors.Human
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"

  test "Formation is one honest four-panel lifecycle", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/formation")
    html = render_async(view)

    assert has_element?(view, "#formation-lifecycle")
    assert html =~ "Form your Regent"
    assert html =~ "Sign in to begin with one Regent tied to your account."

    for panel <- ["overview", "cloud", "hermes_skills", "billing"] do
      assert has_element?(view, ~s([data-formation-panel-content="#{panel}"]))
    end

    refute has_element?(view, "#formation-lifecycle a[href^='/formation/']")
  end

  test "signed-in Formation creates the account's one Regent through the named action", %{
    conn: conn
  } do
    {:ok, account} =
      Accounts.register_verified("did:privy:formation", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/formation")

    html = render_async(view)

    assert html =~ "Signed in as"
    assert html =~ "0x1111…1111"
    assert html =~ "Form your one Regent"
    refute html =~ "Sign in to begin"
    refute html =~ "Sprite is running"

    view
    |> form("#form-regent", regent: %{slug: "atlas", display_name: "Atlas"})
    |> render_submit()

    assert render(view) =~ "Atlas is formed"
    assert has_element?(view, ~s(a[href="/regents/atlas"]), "View public profile")

    assert {:ok, regent} =
             Formation.get_my_regent(actor: %Human{human_account_id: account.id})

    assert regent.slug == "atlas"
  end

  test "a formed Regent can update its public profile without exposing owner data", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:formed", @wallet, [@wallet], actor: %System{})

    Formation.form_regent!("formed-regent", "Formed Regent",
      actor: %Human{human_account_id: account.id}
    )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/formation")

    render_async(view)

    view
    |> form("#update-regent-profile",
      profile: %{display_name: "New Name", summary: "A concise public summary."}
    )
    |> render_submit()

    html = render(view)
    assert html =~ "New Name is formed"
    assert html =~ "A concise public summary."
  end

  test "the owner provisions and refreshes one verified Sprite from the Cloud panel", %{
    conn: conn
  } do
    account =
      Accounts.register_verified!("did:privy:formation-cloud-live", @wallet, [@wallet],
        actor: %System{}
      )

    Formation.form_regent!("cloud-live-regent", "Cloud Live Regent",
      actor: %Human{human_account_id: account.id}
    )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/formation")

    assert has_element?(view, "#provision-cloud-runtime", "Provision Sprite")
    refute has_element?(view, "#formation-cloud-runtime")

    view |> element("#provision-cloud-runtime") |> render_click()

    assert has_element?(view, "#formation-cloud-runtime", "Cloud Live Regent")
    assert has_element?(view, "#formation-cloud-runtime", "cold")
    assert has_element?(view, "#refresh-cloud-runtime", "Refresh status")
    refute render(view) =~ "SPRITES_TOKEN"
    refute has_element?(view, "#formation-cloud-runtime", "Pause")
    refute has_element?(view, "#formation-cloud-runtime", "Resume")

    view |> element("#refresh-cloud-runtime") |> render_click()
    assert render(view) =~ "Sprite status refreshed."
  end

  test "the owner creates a temporary agent code and disconnects a paired agent", %{conn: conn} do
    account =
      Accounts.register_verified!("did:privy:formation-agent-pairing", @wallet, [@wallet],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("agent-pairing-live", "Agent Pairing", actor: actor)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/formation")

    assert has_element?(view, "#request-agent-pairing-code", "Create temporary code")
    refute has_element?(view, "#agent-pairing-code")

    view |> element("#request-agent-pairing-code") |> render_click()
    html = render(view)
    assert html =~ "This code works once"
    assert [_, code] = Regex.run(~r/id="agent-pairing-code".*?<strong>([^<]+)<\/strong>/s, html)

    link =
      Formation.claim_agent_link!(
        regent.id,
        code,
        %{
          agent_id: "agent-live",
          registry_address: "0x1111111111111111111111111111111111111111",
          token_id: "7",
          wallet: "0x2222222222222222222222222222222222222222"
        },
        actor: %System{}
      )

    {:ok, refreshed, _html} =
      conn
      |> recycle()
      |> init_test_session(%{human_account_id: account.id})
      |> live("/formation")

    assert has_element?(refreshed, "#agent-link-#{link.id}", "agent-live")

    refreshed
    |> element("#agent-link-#{link.id} button", "Disconnect")
    |> render_click()

    refute has_element?(refreshed, "#agent-link-#{link.id}")
    assert render(refreshed) =~ "The agent is no longer connected."
    assert {:ok, []} = Formation.list_my_agent_links(regent.id, actor: actor)
  end
end
