defmodule RegentsWeb.Autolaunch.TreasuryController do
  use RegentsWeb, :controller

  alias RegentsWeb.Autolaunch.{ApiError, MarketAnswer}

  # The answer is the one its hosted MCP tool gives too (`RegentsWeb.Autolaunch.MarketAnswer`).
  def show(conn, params), do: ApiError.answer(conn, MarketAnswer.treasury(params))
end
