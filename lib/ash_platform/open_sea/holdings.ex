defmodule AshPlatform.OpenSea.Holdings do
  @moduledoc "Bounded, data-layer-less OpenSea lookup for the three fixed Base collections."
  use Ash.Resource, domain: AshPlatform.OpenSea, authorizers: [Ash.Policy.Authorizer]
  require Logger
  alias AshPlatform.WalletActions.Address

  @collections ["animata", "regent-animata-ii", "regents-club"]
  @max_pages 10
  @request_timeout 5_000
  @lookup_timeout 15_000

  actions do
    action :fetch_owned_collectibles, :map do
      argument :address, :string, allow_nil?: false
      run fn input, _context -> fetch(input.arguments.address) end
    end
  end

  policies do
    policy action(:fetch_owned_collectibles) do
      authorize_if AshPlatform.Staking.Checks.HumanActor
    end
  end

  defp fetch(address) do
    with {:ok, address} <- Address.normalize(address),
         key when is_binary(key) and key != "" <-
           Application.get_env(:ash_platform, :opensea_api_key) do
      task = Task.async(fn -> fetch_all(address, key) end)

      case Task.yield(task, @lookup_timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        _ -> unavailable(:lookup_timeout)
      end
    else
      _ -> unavailable(:missing_key)
    end
  end

  defp fetch_all(address, key) do
    @collections
    |> Task.async_stream(
      fn collection ->
        {collection, fetch_collection(address, collection, key, nil, MapSet.new(), 0, [])}
      end,
      max_concurrency: 3,
      ordered: true,
      timeout: @lookup_timeout,
      on_timeout: :kill_task
    )
    |> Enum.to_list()
    |> Enum.reduce_while({:ok, %{}}, fn
      {:ok, {collection, {:ok, ids}}}, {:ok, acc} -> {:cont, {:ok, Map.put(acc, collection, ids)}}
      _, _ -> {:halt, unavailable(:provider_failure)}
    end)
    |> case do
      {:ok, by_collection} -> {:ok, present(by_collection)}
      error -> error
    end
  end

  defp fetch_collection(_address, _collection, _key, _cursor, _seen, @max_pages, _ids),
    do: unavailable(:page_cap)

  defp fetch_collection(address, collection, key, cursor, seen, pages, ids) do
    with false <- repeated_cursor?(cursor, seen),
         {:ok, nfts, next} <- request_page(address, collection, key, cursor),
         {:ok, page_ids} <- identifiers(nfts) do
      continue_collection(
        next,
        address,
        collection,
        key,
        remember(cursor, seen),
        pages,
        ids ++ page_ids
      )
    else
      true -> unavailable(:repeated_cursor)
      error -> error
    end
  end

  defp request_page(address, collection, key, cursor) do
    url =
      "https://api.opensea.io/api/v2/chain/base/account/#{address}/nfts?collection=#{collection}&limit=100" <>
        if(cursor, do: "&next=#{URI.encode_www_form(cursor)}", else: "")

    options = [
      headers: [{"accept", "application/json"}, {"x-api-key", key}],
      connect_options: [timeout: @request_timeout],
      receive_timeout: @request_timeout,
      pool_timeout: @request_timeout,
      retry: false,
      redirect: false
    ]

    case bounded_get(url, options) do
      {:ok, %{status: status, body: %{"nfts" => nfts} = body}}
      when status in 200..299 and is_list(nfts) ->
        with {:ok, next} <- response_cursor(body["next"]) do
          {:ok, nfts, next}
        end

      _ ->
        unavailable(:provider_failure)
    end
  end

  defp bounded_get(url, options) do
    task = Task.async(fn -> client().get(url, options) end)

    case Task.yield(task, @request_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :request_timeout}
    end
  end

  defp continue_collection(next, address, collection, key, seen, pages, ids)
       when is_binary(next) and next != "",
       do: fetch_collection(address, collection, key, next, seen, pages + 1, ids)

  defp continue_collection(_, _address, _collection, _key, _seen, _pages, ids),
    do: {:ok, Enum.uniq(ids)}

  defp repeated_cursor?(nil, _seen), do: false
  defp repeated_cursor?(cursor, seen), do: MapSet.member?(seen, cursor)
  defp remember(nil, seen), do: seen
  defp remember(cursor, seen), do: MapSet.put(seen, cursor)

  defp response_cursor(nil), do: {:ok, nil}
  defp response_cursor(cursor) when is_binary(cursor), do: {:ok, cursor}
  defp response_cursor(_cursor), do: unavailable(:malformed_response)

  defp identifiers(nfts) do
    Enum.reduce_while(nfts, {:ok, []}, fn nft, {:ok, ids} ->
      case identifier(nft) do
        {:ok, id} -> {:cont, {:ok, [id | ids]}}
        :error -> {:halt, unavailable(:malformed_response)}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      error -> error
    end
  end

  defp identifier(%{"identifier" => id}) when is_binary(id) do
    if String.match?(id, ~r/\A[0-9]+\z/), do: {:ok, String.to_integer(id)}, else: :error
  end

  defp identifier(_), do: :error

  defp present(by) do
    animata =
      for {slug, collection} <- [{"animata", "animata_i"}, {"regent-animata-ii", "animata_ii"}],
          id <- Map.get(by, slug, []),
          do: %{
            collection: collection,
            token_id: Integer.to_string(id),
            label: "#{if collection == "animata_i", do: "Animata I", else: "Animata II"} ##{id}"
          }

    club =
      for id <- Map.get(by, "regents-club", []),
          do: %{
            token_id: id,
            label: "Regents Club ##{id}",
            href:
              "https://opensea.io/assets/base/0x2208aadbdecd47d3b4430b5b75a175f6d885d487/#{id}"
          }

    %{animata: animata, regents_club: club}
  end

  defp client, do: Application.fetch_env!(:ash_platform, :opensea_http_client)

  defp unavailable(reason) do
    Logger.warning("OpenSea owned-NFT lookup unavailable: #{inspect(reason)}")
    {:error, :unavailable}
  end
end
