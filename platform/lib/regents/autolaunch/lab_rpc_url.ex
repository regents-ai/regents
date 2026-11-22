defmodule Regents.Autolaunch.LabRpcUrl do
  @moduledoc """
  The RPC doors of a deployment description.

  `public/1` is the endpoint browsers are given for a Base chain
  (`public_rpc_url` in the Base and Base Stocks descriptions), in every review
  and in the page's list of networks, with which Privy adds a chain that
  neither its own list nor viem's names (a lab chain) to a wallet. Every such
  description names it: an `https://` URL, or loopback `http://127.0.0.1:PORT`
  for a local lab. The site reads Base through its own setting
  (`:base_read_rpc_url`), so these descriptions name no door of its own.

  The Robinhood description still names the site's own endpoint (`rpc_url`,
  `admitted/1`): the one its reads, its receipt checks and the faucet's
  impersonation calls reach. It is privileged and never reaches a browser or a
  log line. Admitted: loopback `http://127.0.0.1:PORT` (a local lab) or an
  `https://` URL. Its wallet door (`public/2`) is `https://` only; a
  description whose own door is loopback may omit it, and then wallets are
  given that loopback door, as the local labs are; any other own door requires
  it, so a keyed endpoint never leaves the server.

  No door admits credentials, a query or a fragment.
  """

  @spec public(term()) :: {:ok, String.t()} | {:error, :missing_public_rpc | :invalid_public_rpc}
  def public(nil), do: {:error, :missing_public_rpc}

  def public(value) do
    case admitted(value) do
      {:ok, url} -> {:ok, url}
      {:error, :rpc_not_admitted} -> {:error, :invalid_public_rpc}
    end
  end

  @spec admitted(term()) :: {:ok, String.t()} | {:error, :rpc_not_admitted}
  def admitted(value) when is_binary(value) do
    case URI.new(value) do
      {:ok, %URI{} = uri} -> admitted_uri(uri)
      {:error, _part} -> {:error, :rpc_not_admitted}
    end
  end

  def admitted(_value), do: {:error, :rpc_not_admitted}

  @spec public(term(), String.t()) ::
          {:ok, String.t()} | {:error, :missing_public_rpc | :invalid_public_rpc}
  def public(nil, rpc_url) do
    if loopback?(rpc_url), do: {:ok, rpc_url}, else: {:error, :missing_public_rpc}
  end

  def public(value, _rpc_url) when is_binary(value) do
    with {:ok, %URI{scheme: "https"} = uri} <- URI.new(value),
         true <- bare?(uri) and host?(uri.host) do
      {:ok, URI.to_string(uri)}
    else
      _ -> {:error, :invalid_public_rpc}
    end
  end

  def public(_value, _rpc_url), do: {:error, :invalid_public_rpc}

  @doc "Whether an admitted door is the loopback one, `http://127.0.0.1:PORT`."
  @spec loopback?(String.t()) :: boolean()
  def loopback?(rpc_url), do: match?({:ok, %URI{host: "127.0.0.1"}}, URI.new(rpc_url))

  # Loopback: `http://127.0.0.1:PORT` with nothing else.
  defp admitted_uri(%URI{scheme: "http", host: "127.0.0.1", port: port, path: path} = uri)
       when path in [nil, ""] do
    if bare?(uri) and port?(port),
      do: {:ok, "http://127.0.0.1:#{port}"},
      else: {:error, :rpc_not_admitted}
  end

  defp admitted_uri(%URI{scheme: "https", host: host} = uri) do
    if bare?(uri) and host?(host),
      do: {:ok, URI.to_string(uri)},
      else: {:error, :rpc_not_admitted}
  end

  defp admitted_uri(_uri), do: {:error, :rpc_not_admitted}

  defp bare?(%URI{userinfo: nil, query: nil, fragment: nil}), do: true
  defp bare?(_uri), do: false

  defp port?(port), do: is_integer(port) and port in 1..65_535

  defp host?(host), do: is_binary(host) and host != ""
end
