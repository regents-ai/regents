defmodule AshPlatform.TestContentProvider do
  @moduledoc false

  @behaviour AshPlatform.ContentProvider

  def load(_route_spec, %{"slug" => "fixture-error"}), do: {:error, :fixture_error}
  def load(_route_spec, %{"slug" => "fixture-crash"}), do: raise("fixture crash")

  def load(_route_spec, %{"slug" => "fixture-blocked"}) do
    owner = Process.whereis(AshPlatform.ContentFixtureObserver)
    send(owner, {:fixture_content_started, self()})

    receive do
      :release_fixture_content ->
        {:ok,
         %AshPlatform.Content{
           eyebrow: "Regents Labs",
           status: :preview,
           title: "Stale fixture",
           summary: "This result must not replace a newer destination.",
           details: []
         }}
    end
  end

  def load(route_spec, params), do: AshPlatform.PublicContent.load(route_spec, params)
end
