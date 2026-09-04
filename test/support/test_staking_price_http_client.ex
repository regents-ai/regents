defmodule AshPlatform.TestStakingPriceHttpClient do
  @moduledoc false

  alias AshPlatform.WalletActions.Abi

  def get(url, options) do
    case Application.get_env(:ash_platform, :test_staking_price_handler) do
      handler when is_function(handler, 2) -> handler.(url, options)
      handler when is_function(handler, 1) -> handler.(url)
      _ -> {:ok, %{status: 200, body: default_body(url)}}
    end
  end

  def pair(address, price_native \\ "0.000000002") do
    %{
      "pairs" => [
        %{
          "priceNative" => price_native,
          "baseToken" => %{"address" => address}
        }
      ]
    }
  end

  def token(pairs) when is_list(pairs), do: %{"pairs" => pairs}

  def weth_usdc(price_usd, liquidity_usd \\ 1_000_000) do
    %{
      "priceUsd" => price_usd,
      "liquidity" => %{"usd" => liquidity_usd},
      "quoteToken" => %{"address" => Abi.usdc_address()}
    }
  end

  def quote_body(url, price_native, eth_usd) do
    cond do
      String.contains?(url, "/pairs/") -> pair(Abi.stake_token_address(), price_native)
      String.contains?(url, "/tokens/") -> token([weth_usdc(eth_usd)])
      true -> %{}
    end
  end

  # An empty token listing cannot name a WETH/USDC quote, so a test that
  # does not install a handler sees an unavailable price.
  defp default_body(url) do
    cond do
      String.contains?(url, "/pairs/") -> pair(Abi.stake_token_address())
      String.contains?(url, "/tokens/") -> token([])
      true -> %{}
    end
  end
end
