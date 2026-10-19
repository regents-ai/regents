defmodule Regents.OutsideRequests do
  @moduledoc """
  The browser test server's Req adapter. A request to this machine goes through
  as usual; any other request is refused before it leaves and its address is
  written to the log the browser checks read after every test, so the run fails
  on it.
  """

  @loopback_hosts ~w(127.0.0.1 localhost ::1)

  def run(%Req.Request{url: %URI{host: host}} = request) when host in @loopback_hosts,
    do: Req.Finch.run(request)

  def run(%Req.Request{url: url} = request) do
    File.write!(log(), "#{url.scheme}://#{url.host}#{url.path}\n", [:append])
    {request, Req.TransportError.exception(reason: :econnrefused)}
  end

  defp log, do: Application.fetch_env!(:regents, __MODULE__)[:log]
end
