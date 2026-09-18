defmodule AshPlatformWeb.FormationLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System

  test "Formation exposes the exact Nous handoff with one heading and no local controls", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/formation")
    html = view |> render_async() |> normalize_whitespace()

    assert has_element?(view, "#formation")
    assert has_element?(view, "#formation h1", "Regent runs best on Hermes")
    assert Regex.scan(~r/<h[1-6]\b/, html) |> length() == 1

    assert html =~ "Create and manage your Regent as a Hermes agent in Nous Portal."

    assert has_element?(
             view,
             ~s(#formation-nous-portal-link[href="https://portal.nousresearch.com/cloud"][target="_blank"][rel="noopener noreferrer"][aria-describedby="formation-nous-portal-disclosure"]),
             "Open Nous Portal"
           )

    assert has_element?(
             view,
             "#formation-nous-portal-disclosure",
             "Nous Portal opens in a new tab. Your Hermes agent can complete Autolaunch in their cloud runtime."
           )

    for selector <- [
          "#formation form",
          "#formation button",
          "#form-regent",
          "#update-regent-profile",
          "#provision-cloud-runtime",
          "#refresh-cloud-runtime",
          "#request-agent-pairing-code",
          "#agent-pairing",
          "#formation-cloud-runtime"
        ] do
      refute has_element?(view, selector)
    end

    for copy <- ["Form your Regent", "Hermes Skills", "Provision Sprite"] do
      refute html =~ copy
    end
  end

  test "signed-in visitors receive the same handoff without Formation actions", %{conn: conn} do
    account =
      Accounts.register_verified!(
        "did:privy:formation-handoff-signed-in",
        "0x1111111111111111111111111111111111111111",
        ["0x1111111111111111111111111111111111111111"],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/formation")

    html = view |> render_async() |> normalize_whitespace()

    assert html =~ "Regent runs best on Hermes"
    assert html =~ "Open Nous Portal"
    refute has_element?(view, "#formation", "0x1111")
    refute has_element?(view, "#formation [phx-click]")
    refute has_element?(view, "#formation [phx-submit]")
  end

  defp normalize_whitespace(html), do: Regex.replace(~r/\s+/, html, " ")
end
