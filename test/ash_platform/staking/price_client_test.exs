defmodule AshPlatform.Staking.PriceClientTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Staking.PriceClient
  alias AshPlatform.TestStakingPriceHttpClient

  setup do
    previous_client = Application.get_env(:ash_platform, :staking_price_http_client)
    previous_handler = Application.get_env(:ash_platform, :test_staking_price_handler)

    on_exit(fn ->
      restore(:staking_price_http_client, previous_client)
      restore(:test_staking_price_handler, previous_handler)
    end)

    :ok
  end

  test "BASE_TOKEN_MISMATCH: a pair for some other token is unavailable" do
    Application.put_env(:ash_platform, :staking_price_http_client, MismatchClient)
    assert PriceClient.quote() == :unavailable
  end

  test "NON_200: a refused pair listing is unavailable" do
    Application.put_env(:ash_platform, :staking_price_http_client, RefusedClient)
    assert PriceClient.quote() == :unavailable
  end

  test "QUOTE: REGENT/ETH times ETH USD is the USD price" do
    Application.put_env(:ash_platform, :test_staking_price_handler, fn url ->
      {:ok,
       %{status: 200, body: TestStakingPriceHttpClient.quote_body(url, "0.000000002", "3000")}}
    end)

    assert PriceClient.quote() == {:ok, "0.000006"}
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

  defp restore(key, previous) do
    if previous,
      do: Application.put_env(:ash_platform, key, previous),
      else: Application.delete_env(:ash_platform, key)
  end
end
