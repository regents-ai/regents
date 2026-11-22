defmodule RegentsWeb.Patchbay.SiteEdition do
  @moduledoc """
  Patchbay edition helper on `one-site`. Only `:main` is served here; the open
  edition moves separately later.
  """

  @type t :: :main

  def init(opts), do: opts
  def call(conn, _opts), do: Plug.Conn.assign(conn, :site_edition, :main)
  def on_mount(_mode, _params, _session, socket), do: {:cont, socket}

  def current, do: :main
  def edition(_conn), do: :main
  def main?(_edition \\ :main), do: true
  def open?(_edition \\ :main), do: false
  def answers?(_conn, _edition), do: true
  def left_out_tools(_edition), do: []
  def url(_edition \\ :main), do: Regents.Patchbay.site_url()
  def within(_edition, fun) when is_function(fun, 0), do: fun.()
end
