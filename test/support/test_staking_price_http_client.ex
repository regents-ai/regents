defmodule AshPlatform.TestStakingPriceHttpClient do
  @moduledoc false

  def get(url, options) do
    case Application.get_env(:ash_platform, :test_staking_price_handler) do
      handler when is_function(handler, 2) -> handler.(url, options)
      handler when is_function(handler, 1) -> handler.(url)
      _ -> {:ok, %{status: 200, body: pair(AshPlatform.WalletActions.Abi.stake_token_address())}}
    end
  end

  def pair(address, price \\ "0.000005845") do
    %{
      "pairs" => [
        %{
          "priceUsd" => price,
          "baseToken" => %{"address" => address}
        }
      ]
    }
  end
end
