defmodule Regents.Agents.AccountReads do
  @moduledoc """
  A paired agent's private reads of its person's account: the account and its
  Points. Each is one action, which the agent API
  (`RegentsWeb.AgentReadsController`) and the hosted MCP server both run, and
  each answers the JSON body the API sends. Only a paired agent
  (`Regents.Actors.Agent`) runs them, whether it signs its own requests or is a
  connected app working here as its paired identity. A read that could not be
  done is refused with the API's code (`Regents.Agents.AccountReads.Refused`).
  """

  use Ash.Resource,
    domain: Regents.Agents,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentPoints.Rules
  alias Regents.Agents.AccountReads.Refused
  alias Regents.Points.Board
  alias Regents.SharedReading
  alias RegentsWeb.PointsEntries

  @points_off "Earning Points is off on this site."

  actions do
    action :account, :map do
      description "Reads the paired account's display name and ENS name, with the pairing."

      run fn _input, %{actor: actor} ->
        case Regents.Accounts.get_human_account(actor.human_account_id, actor: actor) do
          {:ok, account} ->
            {:ok,
             %{
               account: Map.take(account, [:id, :display_name, :ens_name]),
               pairing_id: actor.pairing_id,
               agent_wallet: actor.wallet_address
             }}

          {:error, _} ->
            unavailable()
        end
      end
    end

    # Points as decimal text, the same figures the Points page shows. While the
    # page would show the board as not read, the whole answer is unavailable.
    action :points, :map do
      description "Reads the paired account's Points, as the Points page shows them."

      run fn _input, %{actor: actor} ->
        with {:ok, summary} <- RegentPoints.summary(actor: actor),
             {:ok, %{reading: %{} = board}} <- SharedReading.fetch(Board.key()) do
          earning = Rules.active()
          answer = PointsEntries.answer(summary, board, actor.human_account_id, earning != [])
          {:ok, with_note(answer, earning)}
        else
          _not_read -> unavailable()
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  defp with_note(answer, []), do: Map.put(answer, :note, @points_off)
  defp with_note(answer, _earning), do: answer

  defp unavailable, do: {:error, Refused.exception(code: "unavailable")}
end
