defmodule RegentsWeb.MovedController do
  @moduledoc "Pages that moved: their old addresses send the browser to the new one for good."

  use RegentsWeb, :controller

  def stake(conn, _params), do: conn |> put_status(:moved_permanently) |> redirect(to: ~p"/")
end
