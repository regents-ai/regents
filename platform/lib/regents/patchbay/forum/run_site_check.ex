defmodule Regents.Patchbay.Forum.RunSiteCheck do
  @moduledoc """
  The `:run` action of `Regents.Patchbay.Forum.SiteCheck`: checks one site with
  `Regents.Patchbay.Forum.SiteScan`, keeps the findings, and records the WebMCP tools
  found on the site's board when it has one. Its job is the `:run` trigger.
  """

  use Ash.Resource.ManualUpdate

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.SiteCheck
  alias Regents.Patchbay.Forum.SiteScan

  @impl true
  def update(changeset, _opts, _context) do
    check = changeset.data

    {page_url, whole?, found} = SiteScan.findings(check.domain, [])

    findings =
      Map.put(found, "directory", SiteScan.directory_findings(check.domain, check.findings, []))

    # Patchbay's own job: it answers to nobody's request.
    with {:ok, check} <-
           Forum.record_site_check(
             check,
             %{findings: findings, page_url: page_url, page_whole?: whole?},
             authorize?: false
           ) do
      case Forum.get_site_by_origin(check.domain, authorize?: false) do
        {:ok, site} -> SiteCheck.record_tools(site, check)
        {:error, _no_board} -> :ok
      end

      {:ok, check}
    end
  end
end
