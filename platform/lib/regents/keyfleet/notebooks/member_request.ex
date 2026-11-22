defmodule Regents.Keyfleet.Notebooks.MemberRequest do
  @moduledoc """
  A request to a fleet's hub as one of its members, `subject`, whom the hub
  knows by the pass this site signs for them (`Regents.Keyfleet.Notebooks.Pass`). An
  agent's notebook runs (`Regents.Keyfleet.Notebooks.Runs`) and files
  (`Regents.Keyfleet.Notebooks.Files`) are asked for this way, so the hub keeps each
  change as that member's.
  """

  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.Pass

  @doc "Asks the fleet's hub `method` `path` as `subject`, once."
  def request(fleet_id, subject, method, path, options \\ []) do
    {:ok, address} = Notebooks.hub_address(fleet_id)
    {headers, options} = Keyword.pop(options, :headers, [])

    Notebooks.hub_request(
      fleet_id,
      [
        method: method,
        base_url: address,
        url: path,
        headers: [{"x-keyfleet-assertion", Pass.mint(fleet_id, subject)} | headers],
        retry: false,
        redirect: false,
        # Fly's private hub addresses are IPv6. Mint also falls back to IPv4 for local hubs.
        connect_options: [transport_opts: [inet6: true]],
        receive_timeout: Notebooks.config()[:hub_timeout_ms]
      ] ++ options
    )
  end

  @doc "A notebook's address in the hub's API."
  def notebook_path(project_id, notebook_id),
    do: "/api/v1/projects/#{segment(project_id)}/notebooks/#{segment(notebook_id)}"

  @doc "One part of an address, escaped."
  def segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
