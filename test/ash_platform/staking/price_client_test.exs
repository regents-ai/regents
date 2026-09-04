defmodule AshPlatform.Staking.PriceClientTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Staking.PriceClient

  setup do
    previous = Application.get_env(:ash_platform, :staking_price_http_client)
    on_exit(fn -> restore(previous) end)
    :ok
  end

  test "BASE_TOKEN_MISMATCH: a pair for some other token is unavailable" do
    Application.put_env(:ash_platform, :staking_price_http_client, MismatchClient)
    assert PriceClient.regent_price_usd() == :unavailable
  end

  test "NON_200: a refused pair listing is unavailable" do
    Application.put_env(:ash_platform, :staking_price_http_client, RefusedClient)
    assert PriceClient.regent_price_usd() == :unavailable
  end

  defmodule MismatchClient do
    def get(_url, _options) do
      {:ok,
       %{
         status: 200,
         body:
           AshPlatform.TestStakingPriceHttpClient.pair(
             "0x0000000000000000000000000000000000000001"
           )
       }}
    end
  end

  defmodule RefusedClient do
    def get(_url, _options), do: {:ok, %{status: 500, body: %{}}}
  end

  defp restore(previous) do
    if previous,
      do: Application.put_env(:ash_platform, :staking_price_http_client, previous),
      else: Application.delete_env(:ash_platform, :staking_price_http_client)
  end
end
