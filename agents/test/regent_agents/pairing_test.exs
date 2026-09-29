defmodule RegentAgents.PairingTest do
  use RegentAgents.Case, async: true

  alias RegentAgents.PairingCode

  @wallet "0x2222222222222222222222222222222222222222"
  @other_wallet "0x3333333333333333333333333333333333333333"

  test "a code is short-lived, stored only as a hash, and replaced at most once a minute" do
    owner = person("code")

    assert {:ok, issued} = RegentAgents.issue_pairing_code(actor: owner)
    assert byte_size(issued.code) == 24
    assert DateTime.diff(issued.expires_at, issued.issued_at) == 600

    stored =
      PairingCode
      |> Ash.Query.for_read(:by_code_hash, %{code_hash: PairingCode.hash(issued.code)},
        actor: %Agent{wallet: @wallet}
      )
      |> Ash.read_one!()

    assert stored.privy_user_id == owner.privy_user_id
    refute stored.code_hash == issued.code

    assert {:error,
            %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{reason: :issued_recently}]}} =
             RegentAgents.issue_pairing_code(actor: owner)

    age_code!(owner, 60)
    assert {:ok, replacement} = RegentAgents.issue_pairing_code(actor: owner)
    refute replacement.code == issued.code

    assert {:error, _replaced} =
             RegentAgents.pair_agent(issued.code, "Retired", :hermes,
               actor: %Agent{wallet: @wallet}
             )
  end

  test "a valid code pairs the signing agent with the person who made it, once" do
    owner = person("happy")
    code = code!(owner)

    assert {:ok, agent} =
             RegentAgents.pair_agent(code, "  Sol  ", :claude_code,
               actor: %Agent{wallet: @wallet}
             )

    assert %{
             privy_user_id: "did:privy:happy",
             wallet: @wallet,
             name: "Sol",
             harness: :claude_code
           } =
             agent

    assert {:error, _used} =
             RegentAgents.pair_agent(code, "Again", :muse, actor: %Agent{wallet: @other_wallet})

    assert {:ok, [%{wallet: @wallet}]} = RegentAgents.list_my_agents(actor: owner)
  end

  test "an expired code pairs nobody" do
    owner = person("late")
    code = code!(owner)
    age_code!(owner, 600)

    assert {:error, _expired} =
             RegentAgents.pair_agent(code, "Late", :pi, actor: %Agent{wallet: @wallet})

    assert {:ok, []} = RegentAgents.list_my_agents(actor: owner)
  end

  test "one key belongs to one person" do
    first = person("first")
    second = person("second")
    first_code = code!(first)
    second_code = code!(second)

    assert {:ok, _agent} =
             RegentAgents.pair_agent(first_code, "First", :grok_bot,
               actor: %Agent{wallet: @wallet}
             )

    assert {:error, _taken} =
             RegentAgents.pair_agent(second_code, "Second", :grok_bot,
               actor: %Agent{wallet: @wallet}
             )

    assert {:ok, []} = RegentAgents.list_my_agents(actor: second)
  end

  test "checking in marks the agent's last contact, and a stranger is not paired" do
    owner = person("check")
    paired = RegentAgents.pair_agent!(code!(owner), "Muse", :muse, actor: %Agent{wallet: @wallet})

    assert {:ok, checked_in} = RegentAgents.check_in_agent(actor: %Agent{wallet: @wallet})
    assert checked_in.id == paired.id
    assert DateTime.compare(checked_in.last_contact_at, paired.last_contact_at) == :gt

    assert {:error, _not_paired} =
             RegentAgents.check_in_agent(actor: %Agent{wallet: @other_wallet})
  end

  test "only the owner sees, corrects or unpairs an agent" do
    owner = person("owner")
    other = person("other")

    agent =
      RegentAgents.pair_agent!(code!(owner), "Hermes", :hermes, actor: %Agent{wallet: @wallet})

    assert {:ok, []} = RegentAgents.list_my_agents(actor: other)
    assert {:ok, nil} = RegentAgents.get_my_agent(agent.id, actor: other)

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentAgents.change_agent_harness(agent, :pi, actor: other)

    assert {:error, %Ash.Error.Forbidden{}} = RegentAgents.unpair_agent(agent, actor: other)

    assert {:ok, %{harness: :other}} =
             RegentAgents.change_agent_harness(agent, :other, actor: owner)

    assert :ok = RegentAgents.unpair_agent(agent, actor: owner)
    assert {:ok, []} = RegentAgents.list_my_agents(actor: owner)
  end

  test "a person's agents need a signed-in person" do
    assert {:error, _error} = RegentAgents.list_my_agents(actor: %Agent{wallet: @wallet})
    assert {:error, _error} = RegentAgents.issue_pairing_code(actor: %Agent{wallet: @wallet})
  end
end
