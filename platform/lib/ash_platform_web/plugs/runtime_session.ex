defmodule AshPlatformWeb.Plugs.RuntimeSession do
  @moduledoc false

  def init(opts), do: opts

  def call(conn, _opts) do
    options = Application.fetch_env!(:ash_platform, :session_options)
    Plug.Session.call(conn, Plug.Session.init(options))
  end
end
