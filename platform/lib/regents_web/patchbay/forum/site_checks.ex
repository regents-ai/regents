defmodule RegentsWeb.Patchbay.Forum.SiteChecks do
  @moduledoc """
  A site's check (`Regents.Patchbay.Forum.SiteCheck`) as its page reads it:
  the check as last kept, where it stands, and the words for what it found.

  On patchbay.help, opening a site's page also asks for the check when one is
  due, within the visitor's share, and "Refresh this site" asks for a new one.
  Both queue the check itself, which reads the site, and so come with
  Patchbay's background work; until then a page shows the check as it is kept.
  """

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.{Site, SiteCheck}
  alias RegentsWeb.Patchbay.ReadLimit

  @share 10
  @window_seconds 3600

  @doc "The site's check as last kept, or nil before the first; a read that fails is its error."
  @spec current(String.t()) :: {:ok, Ash.Resource.record() | nil} | {:error, term()}
  def current(domain), do: Forum.get_site_check(domain, not_found_error?: false)

  @doc "Asks for a new check and picture for `site` within the visitor's hourly share."
  def refresh(site, check, visitor) do
    with :ready <- refresh_state(site, check),
         {:ok, _budget} <- ReadLimit.admit("site-check:" <> visitor, @share, @window_seconds) do
      AshOban.run_trigger(site, :refresh_picture)
      {:ok, Forum.refresh_site_check!(site.origin)}
    else
      {:error, :rate_limited, _budget} -> {:limited, check}
      _not_ready -> {:not_ready, check}
    end
  end

  @doc "Where a site's refresh stands: `:refreshing`, `:ready`, or `{:fresh, DateTime.t()}`."
  def refresh_state(site, check) do
    cond do
      (check && SiteCheck.pending?(check)) || Site.picture_pending?(site) -> :refreshing
      site.refresh_due? -> :ready
      true -> {:fresh, last_picture_at(site)}
    end
  end

  defp last_picture_at(site) do
    [site.screenshot_captured_at, site.picture_failed_at]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime)
  end

  @doc "Where a site's check stands, for the words beside it."
  @spec state(Ash.Resource.record() | nil) :: :none | :checking | :failed | :done
  def state(nil), do: :none

  def state(check) do
    cond do
      SiteCheck.pending?(check) -> :checking
      is_nil(check.findings) or check.findings["failed"] == true -> :failed
      true -> :done
    end
  end

  @doc """
  When Patchbay last finished a check of the site: nil before the first,
  `:failed` when the last could not be done. A check on its way keeps the
  time of the one before it.
  """
  @spec last_checked(Ash.Resource.record() | nil) :: DateTime.t() | :failed | nil
  def last_checked(%{findings: %{"failed" => true}}), do: :failed
  def last_checked(%{findings: %{}, checked_at: %DateTime{} = at}), do: at
  def last_checked(_check), do: nil

  @doc """
  Whether a finished check found nothing an agent can use: no WebMCP tool on
  any page it read (`SiteCheck.tools/1`), no MCP server and no agent file.
  """
  @spec nothing?(Ash.Resource.record()) :: boolean()
  def nothing?(check),
    do:
      SiteCheck.tools(check) == [] and
        Enum.all?(~w(servers files), &(check.findings[&1] == []))

  @doc "What an MCP server said when it was asked for its tools."
  @spec server_label(map()) :: String.t()
  def server_label(%{"sign_in" => true}), do: "Asks for a sign-in first"
  def server_label(%{"answered" => false}), do: "Did not answer just now"
  def server_label(%{"tools" => []}), do: "Lists no tools"
  def server_label(%{"tools" => [_one]}), do: "1 tool"
  def server_label(%{"tools" => tools}), do: "#{length(tools)} tools"

  @doc "The name of a kind of file agents read."
  @spec file_label(String.t()) :: String.t()
  def file_label("llms_txt"), do: "llms.txt"
  def file_label("api_catalog"), do: "API catalog"
  def file_label("openapi"), do: "OpenAPI description"
  def file_label("skills"), do: "Agent skills"
  def file_label("skill_md"), do: "skill.md"
  def file_label("agent_card"), do: "Agent card"
end
