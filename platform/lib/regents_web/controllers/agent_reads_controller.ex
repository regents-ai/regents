defmodule RegentsWeb.AgentReadsController do
  @moduledoc """
  Private reads for a distinct, currently paired SIWA agent, each one of
  `Regents.Agents.AccountReads`' actions, which the hosted MCP server runs too.
  """
  use RegentsWeb, :controller

  alias Regents.Agents
  alias Regents.Agents.AccountReads.Refused

  def account(conn, _params), do: answer(conn, Agents.read_account(actor: conn.assigns.actor))

  def balance(conn, _params),
    do: answer(conn, Agents.read_credits_balance(actor: conn.assigns.actor))

  def points(conn, _params),
    do: answer(conn, Agents.read_points_summary(actor: conn.assigns.actor))

  def budget(conn, _params),
    do: answer(conn, Agents.read_credits_budget(actor: conn.assigns.actor))

  def history(conn, _params) do
    case pagination(conn.body_params) do
      {:ok, cursor} ->
        answer(conn, Agents.read_credits_history(cursor, actor: conn.assigns.actor))

      :error ->
        refuse(conn, "invalid_cursor")
    end
  end

  defp pagination(params) when is_map(params) and map_size(params) == 0, do: {:ok, nil}

  defp pagination(%{"after" => cursor} = params)
       when map_size(params) == 1 and is_binary(cursor) and byte_size(cursor) in 1..2048,
       do: {:ok, cursor}

  defp pagination(_), do: :error

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
  def refusal("invalid_cursor"),
    do:
      {422,
       %{
         error: %{
           code: "invalid_cursor",
           message: "That history cursor is invalid.",
           hint:
             "Send after as the previous page's pagination.next_cursor, unchanged, or omit it for the newest entries."
         }
       }}

  # Only a hosted MCP read is refused this way: over HTTP these reads take no
  # input beyond the history's body.
  def refusal("invalid_input"),
    do:
      {422,
       %{
         error: %{
           code: "invalid_input",
           message: "The read could not be made with this input.",
           hint:
             "Call it with no input. Credits history takes after alone, as the previous page's pagination.next_cursor."
         }
       }}

  def refusal("unavailable"),
    do:
      {503,
       %{
         error: %{
           code: "unavailable",
           message: "The private read could not be completed.",
           hint: "Try again in a moment with fresh proof."
         }
       }}
end
