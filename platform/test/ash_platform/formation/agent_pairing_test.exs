defmodule AshPlatform.Formation.AgentPairingTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Formation.AgentPairingCode

  @registry "0x1111111111111111111111111111111111111111"
  @wallet "0x2222222222222222222222222222222222222222"
  @now ~U[2026-08-04 12:00:00.000000Z]

  setup do
    previous_clock = Application.get_env(:ash_platform, :agent_pairing_clock)
    {:ok, clock} = Agent.start_link(fn -> @now end)
    Application.put_env(:ash_platform, :agent_pairing_clock, fn -> Agent.get(clock, & &1) end)

    on_exit(fn -> restore(:agent_pairing_clock, previous_clock) end)

    %{clock: clock}
  end

  test "a code is short-lived, stored only as a hash, and rate limited", %{clock: clock} do
    {account, actor, regent} = account_and_regent!("code")

    assert {:ok, issued} = Formation.issue_agent_pairing_code(regent.id, actor: actor)
    assert issued.expires_at == DateTime.add(@now, 600, :second)
    assert byte_size(issued.code) == 24

    hash = :crypto.hash(:sha256, issued.code) |> Base.encode16(case: :lower)

    stored =
      AgentPairingCode
      |> Ash.Query.for_read(:by_code_hash, %{code_hash: hash}, actor: %System{})
      |> Ash.read_one!()

    assert stored.human_account_id == account.id
    assert stored.regent_id == regent.id
    assert stored.code_hash == hash
    refute stored.code_hash == issued.code

    assert {:error, _error} = Formation.issue_agent_pairing_code(regent.id, actor: actor)

    Agent.update(clock, fn _ -> DateTime.add(@now, 60, :second) end)
    assert {:ok, replacement} = Formation.issue_agent_pairing_code(regent.id, actor: actor)
    refute replacement.code == issued.code

    assert {:error, _error} =
             Formation.claim_agent_link(regent.id, issued.code, identity("retired"),
               actor: %System{}
             )
  end

  test "a valid code creates one durable link and cannot be reused" do
    {_account, actor, regent} = account_and_regent!("happy")
    issued = Formation.issue_agent_pairing_code!(regent.id, actor: actor)

    assert {:ok, link} =
             Formation.claim_agent_link(regent.id, issued.code, identity("happy"),
               actor: %System{}
             )

    assert link.regent_id == regent.id
    assert link.human_account_id == actor.human_account_id
    assert link.agent_id == "agent-happy"
    assert link.registry_address == @registry
    assert link.wallet == @wallet
    assert link.paired_at == @now

    assert {:error, _error} =
             Formation.claim_agent_link(regent.id, issued.code, identity("second"),
               actor: %System{}
             )

    assert {:ok, [owned]} = Formation.list_my_agent_links(regent.id, actor: actor)
    assert owned.id == link.id
  end

  test "expired and unknown codes fail without creating a link", %{clock: clock} do
    {_account, actor, regent} = account_and_regent!("invalid")
    issued = Formation.issue_agent_pairing_code!(regent.id, actor: actor)

    Agent.update(clock, fn _ -> DateTime.add(@now, 601, :second) end)

    for code <- [issued.code, "not-a-real-code"] do
      assert {:error, _error} =
               Formation.claim_agent_link(regent.id, code, identity(code), actor: %System{})
    end

    assert {:ok, []} = Formation.list_my_agent_links(regent.id, actor: actor)
  end

  test "a code cannot bind an agent to another human's Regent" do
    {_first, first_actor, first_regent} = account_and_regent!("first")
    {_second, second_actor, second_regent} = account_and_regent!("second")
    issued = Formation.issue_agent_pairing_code!(first_regent.id, actor: first_actor)

    assert {:error, _error} =
             Formation.claim_agent_link(second_regent.id, issued.code, identity("cross-account"),
               actor: %System{}
             )

    assert {:ok, []} = Formation.list_my_agent_links(first_regent.id, actor: first_actor)
    assert {:ok, []} = Formation.list_my_agent_links(second_regent.id, actor: second_actor)
  end

  test "database uniqueness prevents the same registry identity from pairing twice" do
    {_first, first_actor, first_regent} = account_and_regent!("unique-first")
    {_second, second_actor, second_regent} = account_and_regent!("unique-second")
    first_code = Formation.issue_agent_pairing_code!(first_regent.id, actor: first_actor)
    second_code = Formation.issue_agent_pairing_code!(second_regent.id, actor: second_actor)

    assert {:ok, _link} =
             Formation.claim_agent_link(first_regent.id, first_code.code, identity("unique"),
               actor: %System{}
             )

    assert {:error, _error} =
             Formation.claim_agent_link(second_regent.id, second_code.code, identity("unique"),
               actor: %System{}
             )

    assert {:ok, []} = Formation.list_my_agent_links(second_regent.id, actor: second_actor)
  end

  test "only the owning human can read and revoke a link" do
    {_owner, owner_actor, regent} = account_and_regent!("policy-owner")
    {_other, other_actor, _other_regent} = account_and_regent!("policy-other")
    issued = Formation.issue_agent_pairing_code!(regent.id, actor: owner_actor)

    link =
      Formation.claim_agent_link!(regent.id, issued.code, identity("policy"), actor: %System{})

    assert {:ok, [owned]} = Formation.list_my_agent_links(regent.id, actor: owner_actor)
    assert owned.id == link.id
    assert {:ok, []} = Formation.list_my_agent_links(regent.id, actor: other_actor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Formation.revoke_agent_link(link, actor: other_actor)

    assert :ok = Formation.revoke_agent_link(link, actor: owner_actor)
    assert {:ok, []} = Formation.list_my_agent_links(regent.id, actor: owner_actor)

    for actor <- [nil, %System{}, %{human_account_id: owner_actor.human_account_id}] do
      assert {:error, _error} = Formation.list_my_agent_links(regent.id, actor: actor)
    end
  end

  defp account_and_regent!(suffix) do
    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!(
        "did:privy:agent-pairing:#{suffix}:#{unique}",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}

    regent =
      Formation.form_regent!("pairing-#{suffix}-#{unique}", "Pairing #{suffix}", actor: actor)

    {account, actor, regent}
  end

  defp identity(suffix) do
    %{
      agent_id: "agent-#{suffix}",
      registry_address: @registry,
      token_id: "7",
      wallet: @wallet
    }
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
