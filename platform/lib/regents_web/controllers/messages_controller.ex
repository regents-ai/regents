defmodule RegentsWeb.MessagesController do
  @moduledoc """
  A paired agent leaving a private message for the site's team, under a topic
  the site names, with per-request SIWA proof (`RegentsWeb.Plugs.PairedAgent`).
  Only the team reads them, at /admin/messages.
  """

  use RegentsWeb, :controller

  alias RegentHttp.UnexpectedFailure
  alias Regents.Messages
  alias Regents.Messages.Refused
  alias RegentsWeb.{ClientAddress, FormErrors}

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  @errors %{
    "invalid_message" =>
      {422, "The message could not be left.",
       "details says why. Send {\"body\": \"…\", \"reply_to\": \"…\", \"operation_id\": \"<uuid>\"}: a body of 1 to 2,000 characters, an optional reply_to of up to 200, and a UUID you keep when retrying, to a topic of lowercase letters, numbers and hyphens. After 10 messages in an hour, wait."},
    "idempotency_conflict" =>
      {409, "This operation_id was already used for another message.",
       "Send a new UUID as operation_id for a new message. Keep an operation_id only to retry the same message."},
    "messages_unavailable" =>
      {503, "The message could not be left right now.", "Try again in a moment."}
  }

  # A retry with the operation_id of a message this agent already left answers
  # its receipt (200), and leaves nothing (`Regents.Messages.Message.AgentLeave`).
  def leave(conn, %{"topic" => topic}) do
    case Messages.agent_leave_message(
           topic,
           Map.take(conn.body_params, ["body", "reply_to", "operation_id"]),
           actor: conn.assigns.actor,
           context: %{client_key: ClientAddress.tag(conn)}
         ) do
      {:ok, %{receipt: receipt, replayed: false}} ->
        conn |> put_status(:created) |> json(%{receipt: receipt})

      {:ok, %{receipt: receipt, replayed: true}} ->
        json(conn, %{receipt: receipt})

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        case Enum.find(errors, &is_struct(&1, Refused)) do
          %Refused{code: code} -> refuse(conn, code)
          nil -> refuse(conn, "invalid_message", error)
        end

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("messages_unavailable")
    end
  end

  # `details` says why invalid input was refused.
  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = Map.fetch!(@errors, code)
    body = %{code: code, message: message, hint: hint}
    body = if error, do: Map.put(body, :details, FormErrors.details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end
end
