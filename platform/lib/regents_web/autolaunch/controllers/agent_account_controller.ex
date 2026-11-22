defmodule RegentsWeb.Autolaunch.AgentAccountController do
  @moduledoc """
  Signed private reads and launch draft edits; no wallet, signing or launch
  authority. Each answer is the one its hosted MCP tool gives too
  (`RegentsWeb.Autolaunch.AccountAnswer`).
  """
  use RegentsWeb, :controller
  alias RegentsWeb.Autolaunch.AccountAnswer
  alias RegentsWeb.Autolaunch.ApiError

  def positions(conn, _params),
    do: ApiError.answer(conn, AccountAnswer.positions(conn.assigns.actor))

  def draft(conn, %{"kind" => kind}),
    do: ApiError.answer(conn, AccountAnswer.draft(kind, conn.assigns.actor))

  def save_draft(conn, %{"kind" => kind}),
    do:
      ApiError.answer(conn, AccountAnswer.save_draft(kind, conn.body_params, conn.assigns.actor))
end
