defmodule Regents.Autolaunch.DexScreener do
  @moduledoc """
  Whether DexScreener has a chart for a graduated token's Base pool, which the
  token's page opens as View Chart (`RegentsWeb.Autolaunch.Components.ChartLink`).

  DexScreener is asked at a fixed address, https://api.dexscreener.com/latest/dex/pairs/base/
  and the pool id, which must be 0x and 64 lowercase hex digits, the chain's
  own answer, or nothing is asked. Nothing else goes into the request: no
  header beyond the client's own name, no redirect followed and no second try,
  with a second and a half to connect, two seconds for each part of the answer
  and three for the whole of it. Giving up on a host that has gone quiet can
  take up to five seconds more: Erlang's TLS close waits that long for the far
  side to close too. At most 64 KiB of the answer is read: a longer one is cut
  off there, through Req's own streaming (`into:`), and counts as no.

  The answer is read only as yes or no: yes when it is status 200 with a list
  `pairs` holding one whose `chainId` is "base" and whose `pairAddress` is the
  pool id, in any case; anything else is no. Nothing from the answer is shown,
  linked or logged; a failure is logged by its kind alone (timeout, refused,
  status, malformed, too large). The answer, a failure's no included, is kept a
  minute per pool (`Regents.Autolaunch.PoolCache.chart/2`), so DexScreener is
  asked about a pool at most once a minute however many open its page.
  """
  require Logger

  alias Regents.Autolaunch.PoolCache

  @pairs "https://api.dexscreener.com/latest/dex/pairs/base/"
  @most_bytes 64 * 1024

  @doc "Whether DexScreener has a chart for the Base pool `pool_id`."
  @spec listed?(String.t()) :: boolean()
  def listed?(pool_id) do
    if Regex.match?(~r/\A0x[0-9a-f]{64}\z/, pool_id),
      do: PoolCache.chart(pool_id, fn -> asked(pool_id) end),
      else: false
  end

  defp asked(pool_id) do
    response =
      Req.get(@pairs <> pool_id,
        connect_options: [timeout: 1_500],
        receive_timeout: 2_000,
        request_timeout: 3_000,
        retry: false,
        redirect: false,
        into: &at_most/2
      )

    answer(response, pool_id)
  end

  # The answer's body, read only up to `@most_bytes`: a longer one stops the
  # read there, its body dropped and the response marked.
  defp at_most({:data, data}, {request, response}) do
    body = response.body <> data

    if byte_size(body) > @most_bytes,
      do: {:halt, {request, %{Req.Response.put_private(response, :too_large, true) | body: ""}}},
      else: {:cont, {request, %{response | body: body}}}
  end

  defp answer({:ok, %Req.Response{private: %{too_large: true}}}, _pool_id),
    do: failed("too large")

  defp answer({:ok, %Req.Response{status: 200, body: %{"pairs" => pairs}}}, pool_id)
       when is_list(pairs),
       do: Enum.any?(pairs, &pool?(&1, pool_id))

  # DexScreener's answer for a pool it does not list.
  defp answer({:ok, %Req.Response{status: 200, body: %{"pairs" => nil}}}, _pool_id), do: false
  defp answer({:ok, %Req.Response{status: 200}}, _pool_id), do: failed("malformed")
  defp answer({:ok, %Req.Response{}}, _pool_id), do: failed("status")
  defp answer({:error, %Req.TransportError{reason: :timeout}}, _pool_id), do: failed("timeout")
  defp answer({:error, %Req.TransportError{}}, _pool_id), do: failed("refused")
  defp answer({:error, _unreadable}, _pool_id), do: failed("malformed")

  defp pool?(%{"chainId" => "base", "pairAddress" => address}, pool_id) when is_binary(address),
    do: String.downcase(address) == pool_id

  defp pool?(_pair, _pool_id), do: false

  defp failed(kind) do
    Logger.warning("autolaunch DexScreener chart check failed: #{kind}")
    false
  end
end
