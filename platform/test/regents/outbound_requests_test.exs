defmodule Regents.OutboundRequestsTest do
  # Every other test answers these requests with a stub, so none of them sees
  # the HTTP library refuse the options a real request is sent with. Req 0.7
  # did exactly that: every Base, OpenSea and price read failed before it was
  # sent. These send the site's own requests through the real library.
  use ExUnit.Case, async: false

  alias Regents.OpenSea
  alias Regents.OpenSea.HoldingsCache
  alias Regents.Staking.PriceClient
  alias Regents.WalletActions.Rpc

  # Nothing listens here, so a request the library accepts fails to connect.
  @closed_port "http://127.0.0.1:9"

  setup do
    previous_key = Application.get_env(:regents, :opensea_api_key)

    on_exit(fn ->
      if previous_key,
        do: Application.put_env(:regents, :opensea_api_key, previous_key),
        else: Application.delete_env(:regents, :opensea_api_key)

      Application.delete_env(:regents, :test_open_sea_handler)
      Application.delete_env(:regents, :test_staking_price_handler)
      HoldingsCache.clear()
    end)

    :ok
  end

  # One real connection to Base, through the request every chain reading makes.
  # No client is configured under this key, so the read goes through Req itself.
  test "Base answers the site's own chain read" do
    assert {:ok, %{number: number}} = Rpc.latest_block(client_key: :outbound_base_client)
    assert number > 0
  end

  test "the OpenSea holdings request is one the HTTP library sends" do
    test = self()
    HoldingsCache.clear()
    Application.put_env(:regents, :opensea_api_key, "test-key")

    Application.put_env(:regents, :test_open_sea_handler, fn _url, options ->
      send(test, {:options, options})
      {:ok, %{status: 200, body: %{"nfts" => []}}}
    end)

    assert {:ok, _holdings} = OpenSea.fetch_owned_collectibles("0x" <> String.duplicate("ab", 20))
    assert_received {:options, options}
    assert {:error, %Req.TransportError{}} = Req.get(@closed_port, options)
  end

  test "the REGENT price request is one the HTTP library sends" do
    test = self()

    Application.put_env(:regents, :test_staking_price_handler, fn _url, options ->
      send(test, {:options, options})
      {:ok, %{status: 503, body: ""}}
    end)

    PriceClient.quote()
    assert_received {:options, options}
    assert {:error, %Req.TransportError{}} = Req.get(@closed_port, options)
  end
end
