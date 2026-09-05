defmodule AshPlatform.ContentCoordinator do
  @moduledoc "Runs generation-tagged shell content work inside LiveView's async lifecycle."

  def load(generation, route_spec, params, provider \\ provider()) do
    {generation, provider.load(route_spec, params)}
  end

  defp provider do
    Application.get_env(:ash_platform, :content_provider, AshPlatform.PublicContent)
  end
end
