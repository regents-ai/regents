defmodule AshPlatform.OpenSea.HoldingsTest do
  use ExUnit.Case, async: false

  alias AshPlatform.OpenSea
  alias AshPlatform.OpenSea.HoldingsCache

  @wallet "0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD"
  @normalized "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"

  setup do
    HoldingsCache.clear()
    previous_key = Application.get_env(:ash_platform, :opensea_api_key)
    Application.put_env(:ash_platform, :opensea_api_key, "test-key")

    on_exit(fn ->
      restore(:opensea_api_key, previous_key)
      Application.delete_env(:ash_platform, :test_open_sea_handler)
      Application.delete_env(:ash_platform, :test_open_sea_responses)
      Application.delete_env(:ash_platform, :test_open_sea_watcher)
    end)

    :ok
  end

  test "SAME_WALLET_COALESCING: simultaneous lookups share one provider read" do
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    first = Task.async(fn -> OpenSea.fetch_owned_collectibles(@wallet) end)
    second = Task.async(fn -> OpenSea.fetch_owned_collectibles(@wallet) end)

    assert {:ok, _} = Task.await(first)
    assert {:ok, _} = Task.await(second)
    assert length(requests(3)) == 3
    refute_receive {:open_sea_request, _, _, _}
  end

  test "INVALIDATION: a confirmed redemption starts a fresh lookup without stranding the old one" do
    test_pid = self()

    old =
      Task.async(fn ->
        HoldingsCache.fetch(@normalized, fn ->
          send(test_pid, {:old_lookup_started, self()})

          receive do
            :finish_old_lookup -> {:ok, :old}
          end
        end)
      end)

    assert_receive {:old_lookup_started, old_loader}
    HoldingsCache.invalidate(@normalized)

    assert {:ok, :fresh} = HoldingsCache.fetch(@normalized, fn -> {:ok, :fresh} end)
    send(old_loader, :finish_old_lookup)
    assert {:ok, :old} = Task.await(old)

    assert {:ok, :fresh} =
             HoldingsCache.fetch(@normalized, fn -> flunk("fresh result should be cached") end)
  end

  test "FIXED_BASE_COLLECTIONS: only the three allowed slugs are requested after normalization" do
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    Application.put_env(:ash_platform, :test_open_sea_handler, fn url, options ->
      id = if String.contains?(url, "regents-club"), do: "1123", else: "42"
      assert options[:connect_options] == [timeout: 5_000]
      assert options[:receive_timeout] == 5_000
      assert options[:pool_timeout] == 5_000
      assert options[:retry] == false
      assert options[:redirect] == false
      assert {"x-api-key", "test-key"} in options[:headers]
      {:ok, %{status: 200, body: %{"nfts" => [%{"identifier" => id}]}}}
    end)

    assert {:ok, holdings} = OpenSea.fetch_owned_collectibles(@wallet)
    assert Enum.map(holdings.animata, & &1.label) == ["Animata I #42", "Animata II #42"]
    assert [%{label: "Regents Club #1123"}] = holdings.regents_club

    urls = requests(3)
    assert Enum.all?(urls, &String.contains?(&1, "/chain/base/account/#{@normalized}/nfts?"))

    assert urls
           |> Enum.map(&URI.parse(&1).query)
           |> Enum.map(&URI.decode_query/1)
           |> Enum.map(& &1["collection"])
           |> Enum.sort() == ["animata", "regent-animata-ii", "regents-club"]
  end

  test "CONNECTED_WALLET_ONLY: a valid public wallet can request the fixed collections" do
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())
    assert {:ok, %{animata: [], regents_club: []}} = OpenSea.fetch_owned_collectibles(@wallet)
    assert length(requests(3)) == 3
  end

  test "MISSING_KEY: lookup fails closed without a provider request" do
    Application.put_env(:ash_platform, :opensea_api_key, nil)
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())
    assert {:error, _} = OpenSea.fetch_owned_collectibles(@wallet)
    refute_receive {:open_sea_request, _, _, _}
  end

  test "SEEN_CURSOR: a repeated cursor is rejected after two requests per collection" do
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    Application.put_env(:ash_platform, :test_open_sea_handler, fn _url ->
      {:ok, %{status: 200, body: %{"nfts" => [], "next" => "same"}}}
    end)

    assert {:error, _} = OpenSea.fetch_owned_collectibles(@wallet)
    urls = drain_requests()
    assert length(urls) <= 6
    assert Enum.frequencies_by(urls, &collection/1) |> Map.values() |> Enum.all?(&(&1 <= 2))
  end

  test "BOUNDED_PAGES: each collection stops at ten pages and aggregate requests never exceed thirty" do
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    Application.put_env(:ash_platform, :test_open_sea_handler, fn url ->
      cursor = URI.parse(url).query |> URI.decode_query() |> Map.get("next", "0")
      next = cursor |> String.to_integer() |> Kernel.+(1) |> Integer.to_string()
      {:ok, %{status: 200, body: %{"nfts" => [], "next" => next}}}
    end)

    assert {:error, _} = OpenSea.fetch_owned_collectibles(@wallet)
    urls = drain_requests()
    assert length(urls) == 30

    assert Enum.frequencies_by(urls, &collection/1) == %{
             "animata" => 10,
             "regent-animata-ii" => 10,
             "regents-club" => 10
           }
  end

  test "MALFORMED_EVIDENCE: malformed cursors and NFT identifiers fail closed" do
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    for response <- [
          %{"nfts" => [], "next" => 42},
          %{"nfts" => [%{"identifier" => 42}]},
          %{"nfts" => [%{"identifier" => "-1"}]}
        ] do
      Application.put_env(:ash_platform, :test_open_sea_handler, fn _url ->
        {:ok, %{status: 200, body: response}}
      end)

      assert {:error, _} = OpenSea.fetch_owned_collectibles(@wallet)
      assert length(drain_requests()) == 3
    end
  end

  test "REQUEST_TIMEOUT: each page has one five-second whole-call bound" do
    Application.put_env(:ash_platform, :test_open_sea_watcher, self())

    Application.put_env(:ash_platform, :test_open_sea_handler, fn _url ->
      receive do
        :never_sent -> {:ok, %{status: 200, body: %{"nfts" => []}}}
      end
    end)

    started_at = System.monotonic_time(:millisecond)
    assert {:error, _} = OpenSea.fetch_owned_collectibles(@wallet)
    assert System.monotonic_time(:millisecond) - started_at < 10_000
    assert length(drain_requests()) == 3
  end

  defp requests(count), do: for(_ <- 1..count, do: receive_request())

  defp receive_request do
    receive do
      {:open_sea_request, url, _options, _pid} -> url
    after
      500 -> flunk("expected OpenSea request")
    end
  end

  defp drain_requests(acc \\ []) do
    receive do
      {:open_sea_request, url, _options, _pid} -> drain_requests([url | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp collection(url),
    do: url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("collection")

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
