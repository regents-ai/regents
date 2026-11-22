defmodule RegentsWeb.Keyfleet.Plugs.FleetComingSoon do
  @moduledoc """
  Answers every agent request about a coming-soon fleet with 404
  `fleet_coming_soon`. Such a fleet has no rooms, workspace or proposals and
  no keys to run until it opens, so nothing the request asks for is read or
  written, a sync's check-in included. Requests that name no fleet, and those
  about open or unknown fleets, pass on unchanged. The Claude connector's
  tools refuse it alike (`RegentsWeb.Keyfleet.AgentTools.SignedRequest`,
  `RegentsWeb.Keyfleet.ToolErrors`).
  """
  @behaviour Plug

  import Plug.Conn

  alias Regents.Keyfleet.Fleets
  alias RegentsWeb.Keyfleet.Refusal

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{path_params: %{"fleet_id" => fleet_id}} = conn, _opts) do
    if Fleets.coming_soon?(fleet_id, Fleets.get_fleet!(fleet_id)) do
      conn |> Refusal.json(404, "fleet_coming_soon") |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn
end
