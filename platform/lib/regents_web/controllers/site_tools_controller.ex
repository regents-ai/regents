defmodule RegentsWeb.SiteToolsController do
  @moduledoc """
  The browser tools each Regent site offers on its home page, and how an agent
  connects to siwa-server: what the twin cube's six cards show, for anyone to
  read. The twin cube's own browser tools read them here.
  """

  use RegentsWeb, :controller

  alias Regents.SiteTools

  @errors %{
    "site_not_found" =>
      {404, "There is no site with that name.",
       "Use regents, patchbay, techtree, autolaunch, keyfleet or siwa."},
    "site_unreachable" =>
      {503, "That site's tools could not be read right now.", "Try again in a minute."}
  }

  def show(conn, %{"site" => "siwa"}) do
    json(conn, %{site: "siwa-server", connection: SiteTools.connection_help()})
  end

  def show(conn, %{"site" => site}) do
    case SiteTools.tools(site) do
      {:ok, tools} -> json(conn, %{site: SiteTools.name(site), tools: tools})
      {:error, :unknown_site} -> refuse(conn, "site_not_found")
      {:error, :unreachable} -> refuse(conn, "site_unreachable")
    end
  end

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
