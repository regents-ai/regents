defmodule Regents.Points.Award do
  @moduledoc """
  Offers Regent Points what may earn, inside the transaction that made it, so
  something that rolls back offers nothing. Points decides whether it earns;
  while a rule is off nothing is queued.

    * A new Regent account (`account.activated`), from
      `Regents.Accounts.Signals`. The account is one Regents account on
      every site, so every site names it "regents" and it earns once.
    * A social account linked to an account (`social.x`, `social.github`,
      `social.farcaster`), from `Regents.Accounts.Signals`, keyed by the
      provider and its subject so one social account earns once.
    * An agent paired with its person (`agent.activated`), from
      `RegentAgents.Signals`, keyed by the pairing.
  """

  use Ash.Resource,
    domain: Regents.Points,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Actors.System

  signals_in do
    from Regents.Accounts.Signals do
      on :account_registered, :account_registered
      on :social_linked, :social_linked
    end

    from RegentAgents.Signals do
      on :agent_paired, :agent_paired
    end
  end

  actions do
    action :account_registered do
      argument :signal, Regents.Accounts.Signals.AccountRegistered, allow_nil?: false

      run fn %{arguments: %{signal: signal}}, _context ->
        record(%{
          rule_id: "account.activated",
          source_app: "regents",
          source_kind: "account",
          source_event_key: to_string(signal.account_id)
        })
      end
    end

    action :social_linked do
      argument :signal, Regents.Accounts.Signals.SocialLinked, allow_nil?: false

      run fn %{arguments: %{signal: signal}}, _context ->
        record(%{
          rule_id: "social.#{signal.provider}",
          source_app: "regents",
          source_kind: "linked_identity",
          source_event_key: "#{signal.provider}:#{signal.subject}"
        })
      end
    end

    action :agent_paired do
      argument :signal, RegentAgents.Signals.AgentPaired, allow_nil?: false

      run fn %{arguments: %{signal: signal}}, _context ->
        record(%{
          rule_id: "agent.activated",
          source_app: "regents",
          source_kind: "pairing",
          source_event_key: signal.paired_agent_id
        })
      end
    end
  end

  policies do
    # Reached only through the signals above, after the action that emitted
    # them was allowed; each records as the system, never as the actor.
    policy always() do
      authorize_if always()
    end
  end

  defp record(reference) do
    with {:ok, _event} <- RegentPoints.record_event(reference, actor: %System{}), do: :ok
  end
end
