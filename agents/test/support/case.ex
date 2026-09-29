defmodule RegentAgents.Case do
  @moduledoc "A test with its own database transaction and helpers for people and codes."
  use ExUnit.CaseTemplate

  using do
    quote do
      import RegentAgents.Case
      alias RegentAgents.{Agent, Person}
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(RegentAgents.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  def person(name), do: %RegentAgents.Person{privy_user_id: "did:privy:" <> name}

  def code!(person), do: RegentAgents.issue_pairing_code!(actor: person).code

  @doc "Moves a person's code back in time, as if it had been made `seconds` ago."
  def age_code!(person, seconds) do
    RegentAgents.TestRepo.query!(
      """
      UPDATE regent_agents.pairing_codes
      SET issued_at = issued_at - make_interval(secs => $2),
          expires_at = expires_at - make_interval(secs => $2)
      WHERE privy_user_id = $1
      """,
      [person.privy_user_id, seconds]
    )
  end
end
