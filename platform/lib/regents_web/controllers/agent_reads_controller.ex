defmodule RegentsWeb.AgentReadsController do
  @moduledoc """
  Private reads for a distinct, currently paired SIWA agent, each one of
  `Regents.Agents.AccountReads`' actions, which the hosted MCP server runs too.
  """
  use RegentsWeb, :controller

  alias Regents.Agents
  alias Regents.Agents.AccountReads.Refused

  def account(conn, _params), do: answer(conn, Agents.read_account(actor: conn.assigns.actor))

  def points(conn, _params), do: answer(conn, Agents.read_points(actor: conn.assigns.actor))

  defp answer(conn, {:ok, body}), do: json(conn, body)

  defp answer(conn, {:error, %Ash.Error.Invalid{errors: [%Refused{code: code}]}}),
    do: refuse(conn, code)

  defp answer(conn, {:error, _error}), do: refuse(conn, "unavailable")

  defp refuse(conn, code) do
    {status, body} = refusal(code)
    conn |> put_status(status) |> json(body)
  end

  @doc "A private read's refusal `code`: its HTTP status and the JSON body it answers."
  @spec refusal(String.t()) :: {pos_integer(), map()}
  # Only a hosted MCP read is refused this way: over HTTP these reads take no input.
  def refusal("invalid_input"),
    do:
      {422,
       %{
         error: %{
           code: "invalid_input",
           message: "The read could not be made with this input.",
           hint: "Call it with no input."
         }
       }}

  def refusal("unavailable"),
    do:
      {503,
       %{
         error: %{
           code: "unavailable",
           message: "That could not be reached right now.",
           hint: "Try again in a moment."
         }
       }}
end
