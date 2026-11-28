defmodule RegentsWeb.Keyfleet.AgentChainController do
  @moduledoc """
  The transactions an agent's own wallet sends to act on a fleet's contracts:
  marking its keys present, proposing, voting, cancelling, carrying a
  proposal out, running the daily split, sending the REGENT staking share,
  turning waiting USDC into REGENT, claiming one key's money or every key's
  at once, buying the next Key, claiming a Regents Club Key with its Pass,
  asking again for a Key's draw or ending a wait for it that ran out,
  returning an advance, the token launch's upkeep, and, as a Key's holder,
  issuing, renewing and ending its shards and turning its shards' voting on
  or off.

  Delegates every action to `RegentsWeb.Keyfleet.AgentTools.Chain.Answer` so
  signed HTTP requests and hosted MCP tools stay identical.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Chain.Answer

  def presence(conn, params), do: reply(conn, :presence, params)
  def split(conn, params), do: reply(conn, :split, params)
  def send_share(conn, params), do: reply(conn, :send_share, params)
  def convert(conn, params), do: reply(conn, :convert, params)

  def propose(conn, %{"fleet_id" => fleet_id}),
    do: reply(conn, :propose, Map.put(conn.body_params, "fleet_id", fleet_id))

  def vote(conn, params), do: reply(conn, :vote, params)
  def cancel(conn, params), do: reply(conn, :cancel, params)
  def carry_out(conn, params), do: reply(conn, :carry_out, params)
  def claim(conn, params), do: reply(conn, :claim, params)
  def claim_all(conn, params), do: reply(conn, :claim_all, params)
  def buy(conn, params), do: reply(conn, :buy, params)

  def issue_shard(conn, %{"fleet_id" => fleet_id}) do
    params = conn.body_params |> Map.take(~w(keys wallet days)) |> Map.put("fleet_id", fleet_id)
    reply(conn, :issue_shard, params)
  end

  def end_shard(conn, params), do: reply(conn, :end_shard, params)
  def agent_voting(conn, params), do: reply(conn, :agent_voting, params)
  def club_claim(conn, params), do: reply(conn, :club_claim, params)
  def reveal(conn, params), do: reply(conn, :reveal, params)
  def expire_reveal(conn, params), do: reply(conn, :expire_reveal, params)
  def return_advance(conn, params), do: reply(conn, :return_advance, params)
  def launch_upkeep(conn, params), do: reply(conn, :launch_upkeep, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
