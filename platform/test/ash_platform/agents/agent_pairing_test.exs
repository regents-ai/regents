defmodule AshPlatform.Agents.AgentPairingTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Agents}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Agents.{PairedAgent, PairingCode}

  @agent_wallet "0x2222222222222222222222222222222222222222"
  @other_agent_wallet "0x3333333333333333333333333333333333333333"
  @now ~U[2026-08-04 12:00:00.000000Z]

  setup do
    previous_clock = Application.fetch_env!(:ash_platform, :agent_pairing_clock)
    {:ok, clock} = Agent.start_link(fn -> @now end)
    Application.put_env(:ash_platform, :agent_pairing_clock, fn -> Agent.get(clock, & &1) end)

    on_exit(fn -> Application.put_env(:ash_platform, :agent_pairing_clock, previous_clock) end)

    %{clock: clock}
  end

  test "a code is short-lived, stored only as a hash, and replaced at most once a minute",
       %{clock: clock} do
    {account, actor} = person!("code")

    assert {:ok, issued} = Agents.issue_pairing_code(actor: actor)
    assert issued.expires_at == DateTime.add(@now, 600, :second)
    assert byte_size(issued.code) == 24

    hash = :crypto.hash(:sha256, issued.code) |> Base.encode16(case: :lower)

    stored =
      PairingCode
      |> Ash.Query.for_read(:by_code_hash, %{code_hash: hash}, actor: %System{})
      |> Ash.read_one!()

    assert stored.human_account_id == account.id
    refute stored.code_hash == issued.code

    assert {:error,
            %Ash.Error.Invalid{
              errors: [%Ash.Error.Invalid.Unavailable{reason: :issued_recently}]
            }} = Agents.issue_pairing_code(actor: actor)

    Agent.update(clock, fn _ -> DateTime.add(@now, 60, :second) end)
    assert {:ok, replacement} = Agents.issue_pairing_code(actor: actor)
    refute replacement.code == issued.code

    assert {:error, _error} =
             Agents.pair_agent(issued.code, @agent_wallet, "Retired", :hermes, actor: %System{})
  end

  test "a valid code pairs the signing agent with the person who issued it, once" do
    {account, actor} = person!("happy")
    issued = Agents.issue_pairing_code!(actor: actor)

    assert {:ok, agent} =
             Agents.pair_agent(issued.code, @agent_wallet, "  Sol  ", :hermes, actor: %System{})

    assert agent.human_account_id == account.id
    assert agent.wallet == @agent_wallet
    assert agent.name == "Sol"
    assert agent.harness == :hermes
    assert agent.paired_at == @now
    assert agent.last_contact_at == @now

    assert {:error, _error} =
             Agents.pair_agent(issued.code, @other_agent_wallet, "Again", :muse, actor: %System{})

    assert {:ok, [listed]} = Agents.list_my_agents(actor: actor)
    assert listed.id == agent.id

    assert {:ok, [activity]} = Agents.recent_agent_activity(agent.id, actor: actor)
    assert activity.site == "Regents Labs"
    assert activity.action == "Paired with your account"
  end

  test "expired and unknown codes pair nothing", %{clock: clock} do
    {_account, actor} = person!("invalid")
    issued = Agents.issue_pairing_code!(actor: actor)

    Agent.update(clock, fn _ -> DateTime.add(@now, 601, :second) end)

    for code <- [issued.code, "not-a-real-code"] do
      assert {:error, _error} =
               Agents.pair_agent(code, @agent_wallet, "Late", :pi, actor: %System{})
    end

    assert {:ok, []} = Agents.list_my_agents(actor: actor)
  end

  test "one agent key pairs with one account" do
    {_first, first_actor} = person!("unique-first")
    {_second, second_actor} = person!("unique-second")
    first_code = Agents.issue_pairing_code!(actor: first_actor)
    second_code = Agents.issue_pairing_code!(actor: second_actor)

    assert {:ok, _agent} =
             Agents.pair_agent(first_code.code, @agent_wallet, "First", :grok_bot,
               actor: %System{}
             )

    assert {:error, _error} =
             Agents.pair_agent(second_code.code, @agent_wallet, "Second", :grok_bot,
               actor: %System{}
             )

    assert {:ok, []} = Agents.list_my_agents(actor: second_actor)
  end

  test "checking in updates the last contact and adds to the agent's activity", %{clock: clock} do
    {_account, actor} = person!("check-in")
    issued = Agents.issue_pairing_code!(actor: actor)
    agent = Agents.pair_agent!(issued.code, @agent_wallet, "Muse", :muse, actor: %System{})

    later = DateTime.add(@now, 3600, :second)
    Agent.update(clock, fn _ -> later end)

    assert {:ok, checked_in} = Agents.check_in_agent(@agent_wallet, actor: %System{})
    assert checked_in.id == agent.id
    assert checked_in.last_contact_at == later
    assert checked_in.paired_at == @now

    assert {:ok, [latest, first]} = Agents.recent_agent_activity(agent.id, actor: actor)
    assert {latest.action, latest.occurred_at} == {"Checked in", later}
    assert first.action == "Paired with your account"

    assert {:error, _error} = Agents.check_in_agent(@other_agent_wallet, actor: %System{})
  end

  test "only the person who paired an agent can see, correct or unpair it" do
    {_owner, owner} = person!("policy-owner")
    {_other, other} = person!("policy-other")
    issued = Agents.issue_pairing_code!(actor: owner)
    agent = Agents.pair_agent!(issued.code, @agent_wallet, "Hermes", :hermes, actor: %System{})

    assert {:ok, []} = Agents.list_my_agents(actor: other)
    assert {:ok, nil} = Agents.get_my_agent(agent.id, actor: other)
    assert {:ok, []} = Agents.recent_agent_activity(agent.id, actor: other)

    assert {:error, %Ash.Error.Forbidden{}} =
             Agents.change_agent_harness(agent, :pi, actor: other)

    assert {:error, %Ash.Error.Forbidden{}} = Agents.unpair_agent(agent, actor: other)

    Phoenix.PubSub.subscribe(AshPlatform.PubSub, PairedAgent.topic(owner.human_account_id))

    assert {:ok, %{harness: :openclaw}} =
             Agents.change_agent_harness(agent, :openclaw, actor: owner)

    assert_receive :agents_changed

    assert :ok = Agents.unpair_agent(agent, actor: owner)
    assert_receive :agents_changed
    assert {:ok, []} = Agents.list_my_agents(actor: owner)

    for actor <- [nil, %System{}] do
      assert {:error, _error} = Agents.list_my_agents(actor: actor)
    end
  end

  defp person!(suffix) do
    unique = Elixir.System.unique_integer([:positive])
    wallet = "0x" <> String.pad_leading(Integer.to_string(unique, 16), 40, "0")

    account =
      Accounts.register_verified!("did:privy:agents:#{suffix}:#{unique}", wallet, [wallet],
        actor: %System{}
      )

    {account, %Human{human_account_id: account.id}}
  end
end
