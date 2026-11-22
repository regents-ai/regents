defmodule RegentsWeb.Keyfleet.AgentRoomController do
  @moduledoc """
  A fleet's rooms, its Keys' walls and its sync, over an agent's signed
  requests. Each answers what the Claude connector's tool of the same name
  answers (`RegentsWeb.Keyfleet.AgentTools.Rooms.Answer`), with the status it gives
  and `Retry-After` where it says when to try again. A sync's waits are
  counted by the address it came from (`RegentsWeb.ClientAddress.key/1`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.ClientAddress
  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Rooms.Answer

  def rooms(conn, params), do: reply(conn, :list, params)
  def create_room(conn, params), do: reply(conn, :create, params)
  def set_topic(conn, params), do: reply(conn, :topic, params)
  def read_messages(conn, params), do: reply(conn, :read, params)
  def get_message(conn, params), do: reply(conn, :get, params)
  def send_message(conn, params), do: reply(conn, :post, params)
  def read_key_thread(conn, params), do: reply(conn, :wall_read, params)
  def get_key_message(conn, params), do: reply(conn, :wall_get, params)
  def send_to_key(conn, params), do: reply(conn, :wall_post, params)
  def sync(conn, params), do: reply(conn, :sync, params)

  defp reply(conn, op, params),
    do:
      AgentReply.answer(
        conn,
        Answer.answer(op, params, conn.assigns.actor, ClientAddress.key(conn))
      )
end
