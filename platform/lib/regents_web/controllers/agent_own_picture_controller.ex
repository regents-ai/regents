defmodule RegentsWeb.AgentOwnPictureController do
  @moduledoc """
  A paired agent sets and removes its own picture, re-made as its person's
  upload on the Account page is (`Regents.AgentPicture`). Its pairing names the
  agent, so it can never name another, even one of the same person.
  """
  use RegentsWeb, :controller

  require Logger

  alias Regents.{AgentPicture, RateLimiter}
  alias RegentsWeb.{AgentPictureController, PublicDocuments}
  alias RegentsWeb.Plugs.PairedAgent

  # A signed body is read up to 64 KB (`RegentsWeb.Plugs.AgentBodyReader`), so
  # nothing larger reaches the decoder, and each agent sends at most its
  # allowance an hour, counted before decoding.
  def set(conn, _params) do
    actor = conn.assigns.actor

    with :ok <- admit(actor),
         {:ok, bytes} <- sent_picture(conn.body_params),
         {:ok, webp} <- AgentPicture.make(bytes),
         {:ok, picture} <-
           RegentAgents.set_own_agent_picture(actor.pairing_id, webp, actor: actor) do
      json(conn, %{picture: picture(actor, picture)})
    else
      {:limited, seconds} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(seconds))
        |> refuse("pictures_limited")

      {:error, reason} when is_atom(reason) ->
        refuse(conn, picture_code(reason))

      {:error, %Ash.Error.Forbidden{}} ->
        refuse(conn, "agent_not_paired")

      {:error, %Ash.Error.Invalid{}} ->
        refuse(conn, "agent_not_paired")

      {:error, error} ->
        unavailable(conn, error)
    end
  end

  def remove(conn, _params) do
    actor = conn.assigns.actor

    case RegentAgents.remove_own_agent_picture(actor.pairing_id, actor: actor) do
      :ok ->
        json(conn, %{removed: true})

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} ->
        refuse(conn, "picture_not_found")

      {:error, %Ash.Error.Forbidden{}} ->
        refuse(conn, "agent_not_paired")

      {:error, %Ash.Error.Invalid{}} ->
        refuse(conn, "agent_not_paired")

      {:error, error} ->
        unavailable(conn, error)
    end
  end

  defp admit(actor) do
    allowance = Application.fetch_env!(:regents, :agent_picture_rate_limit)

    case RateLimiter.admit(
           {:agent_picture, actor.wallet_address},
           allowance[:limit],
           allowance[:window_seconds]
         ) do
      {:ok, _budget} -> :ok
      {:error, :rate_limited, budget} -> {:limited, budget.reset}
    end
  end

  defp sent_picture(%{"picture" => encoded}) when is_binary(encoded) do
    with :error <- Base.decode64(encoded), do: {:error, :not_base64}
  end

  defp sent_picture(_params), do: {:error, :not_base64}

  defp unavailable(conn, error) do
    Logger.error("An agent's own picture could not be changed: " <> inspect(error))
    refuse(conn, "unavailable")
  end

  defp picture_code(:not_base64), do: "invalid_picture"
  defp picture_code(:too_big), do: "picture_too_large"
  defp picture_code(:not_a_picture), do: "not_a_picture"
  defp picture_code(:too_detailed), do: "picture_too_detailed"

  defp picture(actor, picture),
    do: %{
      url:
        PublicDocuments.url(
          AgentPictureController.path(String.downcase(actor.wallet_address), picture.updated_at)
        ),
      updated_at: picture.updated_at
    }

  # Every refusal: a code for programs, a message and a hint for people.
  @errors %{
    "invalid_picture" =>
      {422, "Send the picture as base64.",
       "Send picture as the file's bytes in standard base64, with no line breaks: a PNG, JPEG or WebP of up to 45 KB."},
    "picture_too_large" =>
      {413, "That picture is too large.",
       "Send a PNG, JPEG or WebP of up to 45 KB and 100 million pixels."},
    "not_a_picture" =>
      {422, "That file is not a picture we take.", "Send a whole PNG, JPEG or WebP file."},
    "picture_too_detailed" =>
      {422, "That picture is too detailed.",
       "Send a simpler picture: it is kept as a 256 × 256 WebP of up to 64 KB."},
    "picture_not_found" =>
      {404, "You have no picture.", "Set one with regents_agent_picture_set first."},
    "unavailable" =>
      {503, "That could not be reached right now.", "Try again in a moment with fresh proof."}
  }

  defp refuse(conn, "agent_not_paired") do
    {message, hint} = PairedAgent.not_paired()
    error(conn, 403, "agent_not_paired", message, hint)
  end

  defp refuse(conn, "pictures_limited") do
    limit = Application.fetch_env!(:regents, :agent_picture_rate_limit)[:limit]

    error(
      conn,
      429,
      "pictures_limited",
      "You have set your picture #{limit} times this hour.",
      "Wait the number of seconds in Retry-After, then send it again."
    )
  end

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    error(conn, status, code, message, hint)
  end

  defp error(conn, status, code, message, hint) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
