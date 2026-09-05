defmodule AshPlatform.TestOpenSeaHttpClient do
  def get(url, options) do
    if watcher = Application.get_env(:ash_platform, :test_open_sea_watcher),
      do: send(watcher, {:open_sea_request, url, options, self()})

    case Application.get_env(:ash_platform, :test_open_sea_handler) do
      handler when is_function(handler, 2) ->
        handler.(url, options)

      handler when is_function(handler, 1) ->
        handler.(url)

      _ ->
        case Application.get_env(:ash_platform, :test_open_sea_responses, %{}) |> Map.get(url) do
          nil -> {:ok, %{status: 200, body: %{"nfts" => []}}}
          response -> response
        end
    end
  end
end
