defmodule Regents.Account.Points.PairedAgent do
  @moduledoc """
  Regent Points' check of a pairing: it reads the pairing, kept after an
  unpair, and answers with what Points records for the person who made the
  pairing code.

  `existing/2` lists, for `RegentPoints.StartAwards`, each person's earliest
  pairing made before the given time that is still paired, as a lazy stream read
  a page of people at a time; the run asks with its own time.
  """

  alias Regents.Account.Accounts
  alias Regents.Account.Actors.System

  # How many people's accounts one read takes: the most `accounts_by_privy_dids` takes.
  @page 100

  def verify(%{"source_event_key" => id}) do
    case RegentAgents.pairing_history(id) do
      {:ok, %{} = pairing} -> with_account(pairing)
      {:ok, nil} -> {:error, :pairing_not_found}
    end
  end

  # A lazy stream: the pairings come a page of people at a time, and each page's
  # accounts are read in one go.
  def existing("agent.activated", at) do
    at
    |> RegentAgents.pairings_held_from_before()
    |> Stream.chunk_every(@page)
    |> Stream.flat_map(&offers/1)
  end

  defp offers(pairings) do
    accounts =
      pairings
      |> Enum.map(& &1.privy_user_id)
      |> Accounts.accounts_by_privy_dids!(actor: %System{})
      |> Map.new(&{&1.privy_user_id, &1.id})

    for %{privy_user_id: did} = pairing <- pairings, Map.has_key?(accounts, did) do
      {accounts[did],
       %{source_app: "regents", source_kind: "pairing", source_event_key: pairing.id}}
    end
  end

  defp with_account(pairing) do
    case Accounts.get_by_privy_did(pairing.privy_user_id, actor: %System{}) do
      {:ok, %{} = account} -> {:ok, facts(pairing, account)}
      {:ok, nil} -> {:error, :pairing_account_not_found}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp facts(pairing, account) do
    %{
      source_app: "regents",
      source_kind: "pairing",
      source_event_key: pairing.id,
      account_id: account.id,
      actor_kind: "agent",
      # The agent's wallet, so the Points page names the agent the person paired.
      actor_id: pairing.wallet,
      source_action_at: pairing.paired_at,
      qualified_at: pairing.paired_at,
      evidence_ref: "pairing:" <> pairing.id,
      evidence: %{"attribution_link_id" => pairing.id}
    }
  end
end
