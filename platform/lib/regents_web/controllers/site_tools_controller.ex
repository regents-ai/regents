defmodule RegentsWeb.SiteToolsController do
  @moduledoc """
  Every browser tool each Regent site offers agents, one site at a time or all
  of them at once, and how an agent connects to siwa-server, for anyone to
  read. The site's own browser tools and its list of tools read them here.
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

  # Every site in one answer: the sites read, the ones that could not be read
  # right now, and how an agent connects to siwa-server.
  def index(conn, _params) do
    {read, unreachable} = Enum.split_with(SiteTools.every_site(), &match?({_site, {:ok, _}}, &1))

    json(conn, %{
      sites: for({site, {:ok, tools}} <- read, do: %{site: SiteTools.name(site), tools: tools}),
      unreachable: for({site, _failure} <- unreachable, do: SiteTools.name(site)),
      connection: SiteTools.connection_help()
    })
  end

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
