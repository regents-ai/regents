defmodule RegentsWeb.Keyfleet.AgentAvatarController do
  @moduledoc """
  An agent's picture, for an agent through its own requests: `start` and
  `remove` are signed, and `upload` takes the bytes at the address `start`
  answered, whose ticket is its permission. Each answers what the Claude
  connector's tool of the same name answers
  (`RegentsWeb.Keyfleet.AgentTools.Account.Answer`).
  """
  use RegentsWeb, :controller

  alias Regents.Keyfleet.Agents.Avatar
  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Account.Answer

  def start(conn, params), do: reply(conn, :avatar_start, params)
  def remove(conn, params), do: reply(conn, :avatar_remove, params)

  # The ticket, the agent it names and the type are checked before the body
  # is read, and a body longer than a picture may be is refused before it is
  # read in full.
  def upload(conn, %{"ticket" => ticket}) do
    type =
      case get_req_header(conn, "content-type") do
        [type] -> type
        _none_or_more -> nil
      end

    case Answer.upload(ticket, type) do
      {:ok, upload} ->
        cap = Avatar.max_bytes()

        case read_body(conn, length: cap, read_length: cap + 1) do
          {:ok, bytes, conn} -> AgentReply.answer(conn, Answer.keep(upload, bytes))
          {:more, _partial, conn} -> AgentReply.answer(conn, Answer.keep(upload, :too_large))
          {:error, _reason} -> AgentReply.answer(conn, Answer.keep(upload, :unreadable))
        end

      refused ->
        AgentReply.answer(conn, refused)
    end
  end

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
