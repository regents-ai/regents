defmodule AshPlatformWeb.AccountAgentsLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Agents}
  alias AshPlatform.Actors.{Human, System}

  @agent_wallet "0x2222222222222222222222222222222222222222"

  # The sign-in service knows of nothing the agent did unless a test says so.
  setup do
    Req.Test.stub(AshPlatform.Siwa, &Req.Test.json(&1, %{"data" => %{"activity" => []}}))
    :ok
  end

  test "a person makes a pairing code to send their agent, and a second press keeps it", %{
    conn: conn
  } do
    account = register_account("agents-code")
    view = open_account(conn, account)

    assert has_element?(view, "#account-agents p", "No agents are paired yet.")

    view |> element("#account-agents-pair") |> render_click()
    assert has_element?(view, "#account-agents-pairing pre", "Pair with my Regents account.")
    assert has_element?(view, "#account-agents-pairing pre", "https://regents.sh/llms.txt")
    code = pairing_code(view)

    assert has_element?(view, "#account-agents-pair", "Make a new code")
    view |> element("#account-agents-pair") |> render_click()
    assert pairing_code(view) == code

    assert {:ok, agent} =
             Agents.pair_agent(code, @agent_wallet, "Sol", :hermes, actor: %System{})

    # The spent code gives way to the agent that used it.
    assert has_element?(view, "#account-agents-pairing", "Sol paired with your account.")
    refute has_element?(view, "#account-agents-pairing pre")
    assert has_element?(view, "#account-agents-pair", "Pair an agent")
    assert has_element?(view, "#agent-#{agent.id} .account-agent__who span", "Hermes")
    assert has_element?(view, ~s(#agent-#{agent.id} img[src="/images/agents/hermes.png"]))
    assert has_element?(view, "#agent-#{agent.id} .account-agent__contact", "just now")
  end

  test "an agent opens into its details, can be corrected and unpaired", %{conn: conn} do
    account = register_account("agents-detail")
    agent = pair!(account, "Muse helper", :muse)
    view = open_account(conn, account)

    Req.Test.stub(AshPlatform.Siwa, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "activity" => [
            %{
              "audience" => "patchbay",
              "method" => "POST",
              "path" => "/api/agent/reports",
              "occurred_at" => DateTime.to_iso8601(DateTime.utc_now())
            }
          ]
        }
      })
    end)

    view |> element("#agent-#{agent.id} .account-agent__open") |> render_click()

    assert has_element?(view, "#account-agent-dialog[data-open] h2", "Muse helper")
    assert has_element?(view, "#account-agent-dialog dd", @agent_wallet)
    assert has_element?(view, "#account-agent-dialog dt", "First paired")

    render_async(view)
    log = "#account-agent-dialog .account-agent-dialog__log li"
    assert has_element?(view, log, "Asked to make a change")
    assert has_element?(view, log, "Patchbay")
    assert has_element?(view, log, "Paired with your account")

    # A check-in reloads the open agent without blanking what is shown.
    assert {:ok, _agent} = Agents.check_in_agent(@agent_wallet, actor: %System{})
    assert has_element?(view, log, "Patchbay")

    view
    |> form("#account-agent-harness-form", %{"harness" => "pi"})
    |> render_change(%{"agent" => agent.id})

    assert has_element?(view, "#account-agent-dialog .account-kicker", "Pi")
    assert has_element?(view, ~s(#agent-#{agent.id} img[src="/images/agents/pi.svg"]))

    assert has_element?(
             view,
             "#account-agent-dialog-notice[role=status]",
             "Saved. Muse helper runs on Pi."
           )

    view |> element("#account-agent-dialog button", "Unpair") |> render_click()

    refute has_element?(view, "#account-agent-dialog")
    refute has_element?(view, "#agent-#{agent.id}")

    assert has_element?(
             view,
             "#account-agents-notice[role=status]",
             "Muse helper is unpaired. It will need a new code to pair again."
           )

    assert {:ok, []} = Agents.list_my_agents(actor: %Human{human_account_id: account.id})
  end

  test "activity that can't be read says so", %{conn: conn} do
    account = register_account("agents-unread")
    agent = pair!(account, "Quiet", :hermes)
    view = open_account(conn, account)

    Req.Test.stub(AshPlatform.Siwa, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    view |> element("#agent-#{agent.id} .account-agent__open") |> render_click()
    render_async(view)

    assert has_element?(
             view,
             "#account-agent-dialog [role=status]",
             "This agent’s activity couldn’t be read right now."
           )
  end

  test "closing the details leaves only the cards", %{conn: conn} do
    account = register_account("agents-close")
    agent = pair!(account, "Grok", :grok_bot)
    view = open_account(conn, account)

    view |> element("#agent-#{agent.id} .account-agent__open") |> render_click()
    assert has_element?(view, "#account-agent-dialog")

    render_hook(view, "close_agent", %{})
    refute has_element?(view, "#account-agent-dialog")
    assert has_element?(view, "#agent-#{agent.id}")
  end

  test "another person's agent can't be opened, corrected or unpaired", %{conn: conn} do
    owner = register_account("agents-owner")
    agent = pair!(owner, "Private", :hermes)
    other = register_account("agents-other")
    view = open_account(conn, other)

    render_hook(view, "open_agent", %{"id" => agent.id})
    refute has_element?(view, "#account-agent-dialog")

    for {name, params} <- [
          {"change_agent_harness", %{"agent" => agent.id, "harness" => "pi"}},
          {"unpair_agent", %{"id" => agent.id}}
        ] do
      render_hook(view, name, params)

      assert has_element?(
               view,
               "#account-agents-notice[role=alert]",
               "This agent is no longer paired with your account. Nothing changed."
             )
    end

    assert {:ok, [%{harness: :hermes}]} =
             Agents.list_my_agents(actor: %Human{human_account_id: owner.id})
  end

  test "an agent unpaired elsewhere leaves the page, and a late press says so", %{conn: conn} do
    account = register_account("agents-stale")
    agent = pair!(account, "Echo", :hermes)
    view = open_account(conn, account)

    view |> element("#agent-#{agent.id} .account-agent__open") |> render_click()
    :ok = Agents.unpair_agent(agent, actor: %Human{human_account_id: account.id})

    refute has_element?(view, "#account-agent-dialog")
    refute has_element?(view, "#agent-#{agent.id}")

    # A press sent before the page caught up.
    stale = "This agent is no longer paired with your account. Nothing changed."

    for {name, params} <- [
          {"change_agent_harness", %{"agent" => agent.id, "harness" => "pi"}},
          {"unpair_agent", %{"id" => agent.id}}
        ] do
      render_hook(view, name, params)
      assert has_element?(view, "#account-agents-notice[role=alert]", stale)
    end
  end

  test "a choice that isn't on the list, or an agent that isn't one, changes nothing", %{
    conn: conn
  } do
    account = register_account("agents-invalid")
    agent = pair!(account, "Nova", :hermes)
    view = open_account(conn, account)

    view |> element("#agent-#{agent.id} .account-agent__open") |> render_click()
    render_hook(view, "change_agent_harness", %{"agent" => agent.id, "harness" => "nope"})

    assert has_element?(
             view,
             "#account-agent-dialog-notice[role=alert]",
             "Choose what it runs on from the list. Nothing changed."
           )

    assert has_element?(view, "#account-agent-dialog .account-kicker", "Hermes")

    render_hook(view, "unpair_agent", %{"id" => "not-an-agent"})

    assert has_element?(
             view,
             "#account-agent-dialog-notice[role=alert]",
             "This agent is no longer paired with your account. Nothing changed."
           )

    assert {:ok, [%{harness: :hermes}]} =
             Agents.list_my_agents(actor: %Human{human_account_id: account.id})
  end

  test "AGENTS_FOLLOWED_ONLY_HERE: agent changes are heard while the Account page is open",
       %{conn: conn} do
    account = register_account("agents-follow")
    view = open_account(conn, account)
    topic = AshPlatform.Agents.PairedAgent.topic(account.id)

    assert following?(view, topic)

    render_patch(view, "/stake")
    refute following?(view, topic)
    agent = pair!(account, "Away", :hermes)

    render_patch(view, "/account")
    assert following?(view, topic)
    assert has_element?(view, "#agent-#{agent.id}")

    render_patch(view, "/account?again=1")

    assert Registry.lookup(AshPlatform.PubSub, topic) |> Enum.count(&(elem(&1, 0) == view.pid)) ==
             1
  end

  defp following?(view, topic),
    do: Enum.any?(Registry.lookup(AshPlatform.PubSub, topic), &(elem(&1, 0) == view.pid))

  defp pair!(account, name, harness) do
    issued = Agents.issue_pairing_code!(actor: %Human{human_account_id: account.id})
    Agents.pair_agent!(issued.code, @agent_wallet, name, harness, actor: %System{})
  end

  defp pairing_code(view) do
    [_, code] = Regex.run(~r/Pairing code: ([A-Za-z0-9_-]+)/, render(view))
    code
  end

  # A primary name read today keeps the page from asking Ethereum again.
  defp open_account(conn, account) do
    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/account")

    view
  end

  defp register_account(suffix) do
    unique = Elixir.System.unique_integer([:positive])
    wallet = "0x" <> String.pad_leading(Integer.to_string(unique, 16), 40, "0")

    account =
      Accounts.register_verified!("did:privy:#{suffix}:#{unique}", wallet, [wallet],
        actor: %System{}
      )

    Accounts.put_ens_identity(account.id, "#{suffix}.eth", nil, actor: %System{})
    account
  end
end
