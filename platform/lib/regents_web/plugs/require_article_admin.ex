defmodule RegentsWeb.Plugs.RequireArticleAdmin do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(%{path_info: ["admin", "articles"]} = conn, _opts) do
    if Regents.Blog.admin?(conn.assigns.current_human_account) do
      put_resp_header(conn, "cache-control", "no-store")
    else
      raise RegentsWeb.NotFoundError
    end
  end

  def call(conn, _opts), do: conn
end
