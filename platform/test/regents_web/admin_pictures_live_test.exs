defmodule RegentsWeb.AdminPicturesLiveTest do
  # The site's admins remove an agent's picture that breaks the rules at
  # /admin/pictures; anyone else is told the page does not exist.
  use RegentsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Regents.Accounts
  alias Regents.Actors.System

  @agent_wallet "0x44444444444444444444444444444444444444ab"
  # Only its first bytes are judged (RegentAgents.AgentPicture.WebP).
  @webp "RIFF" <> <<0, 0, 0, 0>> <> "WEBP" <> "VP8 "

  setup do
    admins = Application.fetch_env!(:regents, :admins)
    agent_admins = Application.get_env(:regent_agents, :admins)

    on_exit(fn ->
      Application.put_env(:regents, :admins, admins)
      Application.put_env(:regent_agents, :admins, agent_admins)
    end)

    owner = register_account("pictures-owner", "0x5555555555555555555555555555555555555555")
    issued = RegentAgents.issue_pairing_code!(actor: person(owner))

    agent =
      RegentAgents.pair_agent!(issued.code, "Sol", :hermes,
        actor: %RegentAgents.Agent{wallet: @agent_wallet}
      )

    {:ok, _picture} = RegentAgents.set_agent_picture(agent.id, @webp, actor: person(owner))
    %{owner: owner}
  end

  test "an admin finds an agent's picture by its address and removes it", %{conn: conn} do
    admin = register_account("pictures-admin", "0x6666666666666666666666666666666666666666")
    Application.put_env(:regents, :admins, [admin.privy_user_id])
    Application.put_env(:regent_agents, :admins, [admin.privy_user_id])

    {:ok, view, _html} =
      conn |> init_test_session(%{human_account_id: admin.id}) |> live("/admin/pictures")

    view |> form("#admin-pictures-form", wallet: "0x12") |> render_submit()

    assert has_element?(
             view,
             "#admin-pictures-wallet-errors",
             "Enter the agent's full 0x address."
           )

    # Typed in capitals with spaces around it, it names the same agent.
    "0x" <> hex = @agent_wallet
    typed = " 0x#{String.upcase(hex)} "
    view |> form("#admin-pictures-form", wallet: typed) |> render_submit()
    refute has_element?(view, "#admin-pictures-wallet-errors p")

    assert has_element?(
             view,
             "#admin-pictures-picture img[src^='/agents/#{@agent_wallet}/picture']"
           )

    view |> element("#admin-pictures-picture button", "Remove") |> render_click()
    assert has_element?(view, "#admin-pictures-note[role=status]", "Picture removed.")
    refute has_element?(view, "#admin-pictures-picture")
    assert {:ok, nil} = RegentAgents.agent_picture(@agent_wallet)

    view |> form("#admin-pictures-form", wallet: @agent_wallet) |> render_submit()
    assert has_element?(view, "#admin-pictures-none-address-full", @agent_wallet)
  end

  test "anyone but an admin gets the not-found page", %{conn: conn, owner: owner} do
    assert conn |> get("/admin/pictures") |> response(404)

    signed_in = init_test_session(conn, %{human_account_id: owner.id})
    assert signed_in |> get("/admin/pictures") |> response(404)

    assert {:ok, %RegentAgents.AgentPicture{}} = RegentAgents.agent_picture(@agent_wallet)
  end

  defp person(account), do: %RegentAgents.Person{privy_user_id: account.privy_user_id}

  defp register_account(suffix, wallet) do
    Accounts.register_verified!("did:privy:#{suffix}", wallet, [wallet], actor: %System{})
  end
end
