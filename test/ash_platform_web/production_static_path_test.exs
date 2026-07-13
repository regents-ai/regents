defmodule AshPlatformWeb.ProductionStaticPathTest do
  use ExUnit.Case, async: true

  test "production loads Phoenix's digested static manifest" do
    config = Config.Reader.read!("config/prod.exs", env: :prod, imports: :disabled)

    endpoint =
      config
      |> Keyword.fetch!(:ash_platform)
      |> Keyword.fetch!(AshPlatformWeb.Endpoint)

    assert endpoint[:cache_static_manifest] == "priv/static/cache_manifest.json"
  end
end
