defmodule RegentsWeb.Keyfleet.AgentReply do
  @moduledoc """
  Sends an agent tool's answer, `{status, body, retry_after}`, as its signed
  request's reply: the status, the JSON body and, when the answer says when
  to try again, `Retry-After`.
  """

  import Plug.Conn

  @spec answer(Plug.Conn.t(), {pos_integer(), map(), pos_integer() | nil}) :: Plug.Conn.t()
  def answer(conn, {status, body, retry_after}) do
    conn
    |> retry_after(retry_after)
    |> put_status(status)
    |> Phoenix.Controller.json(body)
  end

  defp retry_after(conn, nil), do: conn

  defp retry_after(conn, seconds),
    do: put_resp_header(conn, "retry-after", Integer.to_string(seconds))
end
