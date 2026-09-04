defmodule AshPlatform.Staking.PriceClient do
  @moduledoc """
  REGENT's USD price as the pool it trades in lists it on DexScreener, which is
  also the chart the site sends visitors to.
  """

  alias AshPlatform.WalletActions.Abi

  @pool "0x4ed3b69ac263ad86482f609b2c2105f64bcfd3a7e02e8e078ec9fec1f0324bed"
  @timeout 4_000

  @doc "The Uniswap pool REGENT trades in, as DexScreener names it."
  def pool, do: @pool

  @doc """
  REGENT's USD price on the pool, or `:unavailable`.

  The pair is trusted only when its base token is the staking token. A refused
  or misshapen listing is unavailable and never a guessed figure.
  """
  def regent_price_usd do
    case fetch() do
      {:ok, %{status: 200, body: body}} -> price_from(body)
      _ -> :unavailable
    end
  end

  defp fetch do
    client().get("https://api.dexscreener.com/latest/dex/pairs/base/#{@pool}",
      connect_options: [timeout: @timeout],
      receive_timeout: @timeout,
      pool_timeout: @timeout,
      retry: false,
      redirect: false
    )
  rescue
    error -> {:error, error}
  end

  defp price_from(%{"pairs" => [pair | _]}) when is_map(pair) do
    with address when is_binary(address) <- get_in(pair, ["baseToken", "address"]),
         true <- String.downcase(address) == String.downcase(Abi.stake_token_address()),
         price when is_binary(price) and price != "" <- pair["priceUsd"],
         {_decimal, ""} <- Decimal.parse(price) do
      price
    else
      _ -> :unavailable
    end
  end

  defp price_from(_body), do: :unavailable

  defp client,
    do:
      Application.get_env(
        :ash_platform,
        :staking_price_http_client,
        AshPlatform.Staking.PriceHttpClient
      )
end
