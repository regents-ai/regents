defmodule AshPlatformWeb.ClientAddress do
  @moduledoc """
  The rate-limit key for the client behind a request, and where it came from.

  Fly terminates the connection, so the peer is the proxy and the client
  address arrives in one header the proxy sets itself. Anything but exactly one
  parseable value keys the proxy-wide peer bucket rather than a second header a
  client could forge itself a private budget with.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @spec key(Plug.Conn.t()) :: {:inet.ip_address(), :client_header | :peer_fallback}
  def key(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [value] -> parsed(value, conn.remote_ip)
      _absent_or_duplicated -> {normalized(conn.remote_ip), :peer_fallback}
    end
  end

  defp parsed(value, remote_ip) do
    case value |> :binary.bin_to_list() |> :inet.parse_strict_address() do
      {:ok, address} -> {normalized(address), :client_header}
      {:error, :einval} -> {normalized(remote_ip), :peer_fallback}
    end
  end

  # The mapped and compatible IPv6 spellings of one IPv4 address share its
  # bucket, and a genuine IPv6 client is keyed by its /64 so one host cannot
  # spend the budget once per address in the block it was handed. The key is
  # never persisted, rendered or logged; it lives only in the limiter.
  defp normalized({_, _, _, _} = ipv4), do: ipv4

  defp normalized({0, 0, 0, 0, 0, embedding, high, low}) when embedding in [0, 0xFFFF] do
    <<a, b, c, d>> = <<high::16, low::16>>
    {a, b, c, d}
  end

  defp normalized({a, b, c, d, _, _, _, _}), do: {a, b, c, d, 0, 0, 0, 0}
end
