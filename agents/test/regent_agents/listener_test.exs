defmodule RegentAgents.ListenerTest do
  # These changes commit, as they do on a live site, so the listener hears them
  # through the database the way every other site would. The test removes what
  # it committed.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias RegentAgents.{Agent, Person, TestRepo}

  @wallet "0x4444444444444444444444444444444444444444"

  test "pairing, a check-in, a correction and unpairing are heard through the shared database" do
    owner = %Person{privy_user_id: "did:privy:heard-#{System.unique_integer([:positive])}"}
    agent = %Agent{wallet: @wallet}
    Phoenix.PubSub.subscribe(RegentAgents.TestPubSub, RegentAgents.topic(owner.privy_user_id))

    Sandbox.unboxed_run(TestRepo, fn ->
      try do
        code = RegentAgents.issue_pairing_code!(actor: owner).code
        paired = RegentAgents.pair_agent!(code, "Heard", :hermes, actor: agent)
        assert_receive :agents_changed

        RegentAgents.check_in_agent!(actor: agent)
        assert_receive :agents_changed

        RegentAgents.change_agent_harness!(paired, :pi, actor: owner)
        assert_receive :agents_changed

        RegentAgents.unpair_agent!(paired, actor: owner)
        assert_receive :agents_changed
      after
        for table <- ["pairing_codes", "paired_agents"] do
          TestRepo.query!("DELETE FROM regent_agents.#{table} WHERE privy_user_id = $1", [
            owner.privy_user_id
          ])
        end
      end
    end)

    refute_receive :agents_changed
  end
end
