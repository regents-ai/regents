defmodule RegentsWeb.Patchbay.OffersGate do
  @moduledoc """
  The gate on agent offers' addresses (`Regents.Patchbay.Offers.enabled?/0`): while no
  market is set, a request answers the site's own 404 and a
  connected page goes to the home page, as `RegentsWeb.Patchbay.Showcase` gates the
  motion lab.
  """
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Regents.Patchbay.Offers.enabled?() or raise RegentsWeb.NotFoundError
    conn
  end

  def on_mount(:default, _params, _session, socket) do
    if Regents.Patchbay.Offers.enabled?(),
      do: {:cont, socket},
      else: {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
  end
end
