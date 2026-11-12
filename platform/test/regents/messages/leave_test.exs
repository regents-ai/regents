defmodule Regents.Messages.LeaveTest do
  # Leaving a message for the site's team, through the actions every surface calls:
  # - a signed-in person and a paired agent each leave one, recorded as themselves
  #   (the agent with its person), and get its receipt;
  # - who left it comes from the actor alone: no input can name a sender;
  # - the topic, the text and reply_to are bounded, and nothing is kept when refused;
  # - an operation_id answers its first message again, and refuses any other use;
  # - each person, with their agents, leaves 10 an hour;
  # - only the site's admins read messages.
  use ExUnit.Case, async: false

  alias Regents.{Accounts, Messages, Repo}
  alias Regents.Actors.{Admin, Agent, Human, System}
  alias Regents.Messages.{Message, Refused}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    Regents.RateLimiter.reset()
    on_exit(&Regents.RateLimiter.reset/0)
    %{key: Ecto.UUID.generate()}
  end

  test "a person and a paired agent each leave a message as themselves", %{key: key} do
    {person, account} = person()

    assert {:ok, %Message{} = left} =
             Messages.leave_message(
               %{topic: "agents", body: "Hello team", reply_to: "me@example.com"},
               actor: person,
               context: %{client_key: key}
             )

    assert Message.receipt(left) == %{id: left.id, topic: "agents", inserted_at: left.inserted_at}

    assert %{human_account_id: id, agent_wallet_address: nil, sender_name: name} = stored(left.id)
    assert {id, name} == {account.id, Regents.PublicIdentity.label(account)}

    {agent, account} = paired_agent()

    assert {:ok, %{replayed: false, receipt: %{id: id, topic: "watchdog"}}} =
             leave(agent, "watchdog", %{body: "From an agent"}, key)

    assert %{human_account_id: human, agent_wallet_address: wallet, reply_to: nil} = stored(id)
    assert {human, wallet} == {account.id, agent.wallet_address}
  end

  test "no input names the sender, so a message is never left as anyone else", %{key: key} do
    {person, _account} = person()
    {_other, other} = person()
    count = count()

    assert {:error, %Ash.Error.Invalid{}} =
             Messages.leave_message(
               %{topic: "agents", body: "Hi", human_account_id: other.id, sender_name: "Other"},
               actor: person,
               context: %{client_key: key}
             )

    {agent, _account} = paired_agent()

    assert {:error, %Ash.Error.Invalid{}} =
             leave(agent, "agents", %{body: "Hi", agent_wallet_address: wallet()}, key)

    assert count() == count
  end

  test "the topic, the text and reply_to are bounded, and a refusal keeps nothing", %{key: key} do
    {agent, _account} = paired_agent()
    count = count()

    for {topic, input} <- [
          {"agents", %{body: String.duplicate("a", 2001)}},
          {"agents", %{body: ""}},
          {"agents", %{body: "Hi", reply_to: String.duplicate("a", 201)}},
          {"agents", %{body: "Hi\u202Eevil"}},
          {"Agents!", %{body: "Hi"}},
          {String.duplicate("a", 41), %{body: "Hi"}}
        ] do
      assert {:error, %Ash.Error.Invalid{}} = leave(agent, topic, input, key)
    end

    assert {:ok, _} = leave(agent, "agents", %{body: String.duplicate("a", 2000)}, key)
    assert count() == count + 1
  end

  test "an operation_id answers its first message again and refuses any other use", %{key: key} do
    {agent, _account} = paired_agent()
    operation = Ecto.UUID.generate()
    input = %{body: "Once", reply_to: "a room", operation_id: operation}

    again = fn topic, input ->
      Messages.agent_leave_message(topic, input, actor: agent, context: %{client_key: key})
    end

    assert {:ok, %{replayed: false, receipt: receipt}} = again.("agents", input)
    assert {:ok, %{replayed: true, receipt: ^receipt}} = again.("agents", input)

    for {topic, changed} <- [
          {"agents", %{input | body: "Twice"}},
          {"agents", %{input | reply_to: "elsewhere"}},
          {"watchdog", input}
        ] do
      assert {:error, %{errors: [%Refused{code: "idempotency_conflict"}]}} =
               again.(topic, changed)
    end

    assert count_by(agent) == 1

    # Another agent's same operation_id is its own.
    {other, _account} = paired_agent()

    assert {:ok, %{replayed: false}} =
             Messages.agent_leave_message("agents", input,
               actor: other,
               context: %{client_key: key}
             )
  end

  test "each person, with their paired agents, leaves 10 messages an hour" do
    {agent, account} = paired_agent()

    for n <- 1..10 do
      assert {:ok, _} = leave(agent, "agents", %{body: "Message #{n}"}, Ecto.UUID.generate())
    end

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :body}]}} =
             leave(agent, "agents", %{body: "One more"}, Ecto.UUID.generate())

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :body}]}} =
             Messages.leave_message(%{topic: "agents", body: "Me too"},
               actor: %Human{human_account_id: account.id},
               context: %{client_key: Ecto.UUID.generate()}
             )

    assert count_by(agent) == 10

    {person, _account} = person()

    assert {:ok, _} =
             Messages.leave_message(%{topic: "agents", body: "Still free"},
               actor: person,
               context: %{client_key: Ecto.UUID.generate()}
             )
  end

  test "each network leaves 30 messages an hour, whoever sends them" do
    key = Ecto.UUID.generate()

    for n <- 1..30 do
      {person, _account} = person()
      leave = %{topic: "agents", body: "Message #{n}"}
      assert {:ok, _} = Messages.leave_message(leave, actor: person, context: %{client_key: key})
    end

    {person, _account} = person()

    assert {:error, %Ash.Error.Invalid{}} =
             Messages.leave_message(%{topic: "agents", body: "One more"},
               actor: person,
               context: %{client_key: key}
             )
  end

  test "only the site's admins read messages", %{key: key} do
    {person, _account} = person()

    {:ok, left} =
      Messages.leave_message(%{topic: "agents", body: "Private"},
        actor: person,
        context: %{client_key: key}
      )

    did = "did:privy:admin-" <> Ecto.UUID.generate()
    put_admins([did])

    assert %{results: results} = Messages.list_messages!(actor: %Admin{privy_user_id: did})
    assert left.id in Enum.map(results, & &1.id)

    {agent, _account} = paired_agent()

    for reader <- [person, agent, %Admin{privy_user_id: "did:privy:not-listed"}, nil] do
      assert {:error, %Ash.Error.Forbidden{}} = Messages.list_messages(actor: reader)
    end
  end

  defp leave(agent, topic, input, key) do
    Messages.agent_leave_message(
      topic,
      Map.put_new(input, :operation_id, Ecto.UUID.generate()),
      actor: agent,
      context: %{client_key: key}
    )
  end

  # What was stored, read past the policies: only the site's admins may read.
  defp stored(id), do: Ash.get!(Message, id, authorize?: false)
  # Counted past the policies, which let only the site's admins read.
  defp count, do: Message |> Ash.read!(authorize?: false) |> length()

  defp count_by(agent) do
    # Counted past the policies, which let only the site's admins read.
    messages = Ash.read!(Message, authorize?: false)
    Enum.count(messages, &(&1.agent_wallet_address == agent.wallet_address))
  end

  defp put_admins(admins) do
    old = Application.fetch_env!(:regent_credits, :admins)
    Application.put_env(:regent_credits, :admins, admins)
    on_exit(fn -> Application.put_env(:regent_credits, :admins, old) end)
  end

  defp person do
    did = "did:privy:message-" <> Ecto.UUID.generate()
    wallet = wallet()
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    {%Human{human_account_id: account.id, wallet_addresses: [wallet]}, account}
  end

  defp paired_agent do
    did = "did:privy:message-" <> Ecto.UUID.generate()
    person_wallet = wallet()
    agent_wallet = wallet()
    account = Accounts.register_verified!(did, person_wallet, [person_wallet], actor: %System{})
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})

    pairing =
      RegentAgents.pair_agent!(code.code, "Agent", :codex,
        actor: %RegentAgents.Agent{wallet: agent_wallet}
      )

    {Agent.paired(agent_wallet, pairing, account), account}
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
