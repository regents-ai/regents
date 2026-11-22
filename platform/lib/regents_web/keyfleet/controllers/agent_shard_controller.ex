defmodule RegentsWeb.Keyfleet.AgentShardController do
  @moduledoc """
  The signed-in agent's active shards, one per key, each with the
  transaction that ends it. It answers what the Claude connector's
  `shards_list` answers (`RegentsWeb.Keyfleet.AgentTools.Keys.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Keys.Answer

  def index(conn, params),
    do: AgentReply.answer(conn, Answer.answer(:shards, params, conn.assigns.actor, nil))
end
