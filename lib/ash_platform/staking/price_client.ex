defmodule AshPlatform.Staking.PriceClient do
  @moduledoc """
  REGENT's USD price as REGENT/ETH on the pool it trades in, times ETH/USD.

  The pool is the same one the site sends visitors to. ETH/USD is WETH quoted
  in USDC on Base. Either listing refused or misshapen is unavailable and never
  a guessed figure.
  """

  alias AshPlatform.WalletActions.Abi

  @pool "0x4ed3b69ac263ad86482f609b2c2105f64bcfd3a7e02e8e078ec9fec1f0324bed"
  @weth "0x4200000000000000000000000000000000000006"
  @timeout 4_000

  @doc "The Uniswap pool REGENT trades in, as DexScreener names it."
  def pool, do: @pool

  @doc """
  REGENT's USD price from REGENT/ETH × ETH/USD, or `:unavailable`.

  The REGENT pair is trusted only when its base token is the staking token and
  `priceNative` parses as a Decimal. ETH/USD is the WETH/USDC pair on Base
  with the most USD liquidity.
  """
  def quote do
    with {:ok, eth_ratio} <- regent_eth(),
         {:ok, eth_usd} <- eth_usd() do
      {:ok,
       eth_ratio
       |> Decimal.mult(eth_usd)
       |> Decimal.normalize()
       |> Decimal.to_string(:normal)}
    else
      _ -> :unavailable
    end
  end

  defp regent_eth do
    case get("https://api.dexscreener.com/latest/dex/pairs/base/#{@pool}") do
      {:ok, %{status: 200, body: body}} -> eth_ratio_from(body)
      _ -> :unavailable
    end
  end

  defp eth_usd do
    case get("https://api.dexscreener.com/latest/dex/tokens/#{@weth}") do
      {:ok, %{status: 200, body: body}} -> eth_usd_from(body)
      _ -> :unavailable
    end
  end

  defp eth_ratio_from(%{"pairs" => [pair | _]}) when is_map(pair) do
    with address when is_binary(address) <- get_in(pair, ["baseToken", "address"]),
         true <- String.downcase(address) == String.downcase(Abi.stake_token_address()),
         price when is_binary(price) and price != "" <- pair["priceNative"],
         {decimal, ""} <- Decimal.parse(price) do
      {:ok, decimal}
    else
      _ -> :unavailable
    end
  end

  defp eth_ratio_from(_body), do: :unavailable

  defp eth_usd_from(%{"pairs" => pairs}) when is_list(pairs) do
    usdc = String.downcase(Abi.usdc_address())

    case pairs
         |> Enum.filter(&usdc_quote?(&1, usdc))
         |> Enum.max_by(&liquidity_usd/1, fn -> nil end) do
      nil ->
        :unavailable

      pair ->
        with price when is_binary(price) and price != "" <- pair["priceUsd"],
             {decimal, ""} <- Decimal.parse(price) do
          {:ok, decimal}
        else
          _ -> :unavailable
        end
    end
  end

  defp eth_usd_from(_body), do: :unavailable

  defp usdc_quote?(pair, usdc) when is_map(pair) do
    case get_in(pair, ["quoteToken", "address"]) do
      address when is_binary(address) -> String.downcase(address) == usdc
      _ -> false
    end
  end

  defp usdc_quote?(_pair, _usdc), do: false

  defp liquidity_usd(pair) do
    case get_in(pair, ["liquidity", "usd"]) do
      usd when is_number(usd) ->
        usd

      usd when is_binary(usd) ->
        case Float.parse(usd) do
          {amount, ""} -> amount
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp get(url) do
    client().get(url,
      connect_options: [timeout: @timeout],
      receive_timeout: @timeout,
      pool_timeout: @timeout,
      retry: false,
      redirect: false
    )
  rescue
    error -> {:error, error}
  end

  defp client,
    do:
      Application.get_env(
        :ash_platform,
        :staking_price_http_client,
        AshPlatform.Staking.PriceHttpClient
      )
end
