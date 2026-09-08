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

  @tag :tmp_dir
  test "the endpoint serves fingerprinted root icons", %{tmp_dir: tmp_dir} do
    static_dir = Application.app_dir(:ash_platform, "priv/static")
    icons = ~w(favicon.svg favicon-32.png apple-touch-icon.png)

    for icon <- icons, do: File.cp!(Path.join(static_dir, icon), Path.join(tmp_dir, icon))
    assert :ok = Phoenix.Digester.compile(tmp_dir, tmp_dir, false)
    manifest = tmp_dir |> Path.join("cache_manifest.json") |> File.read!() |> Jason.decode!()

    for icon <- icons do
      digested = Map.fetch!(manifest["latest"], icon)
      destination = Path.join(static_dir, digested)

      unless File.exists?(destination) do
        File.cp!(Path.join(tmp_dir, digested), destination)
        on_exit(fn -> File.rm!(destination) end)
      end

      conn =
        :get
        |> Plug.Test.conn("/#{digested}?vsn=d")
        |> AshPlatformWeb.Endpoint.call(AshPlatformWeb.Endpoint.init([]))

      assert conn.status == 200
      assert conn.resp_body == File.read!(Path.join(static_dir, icon))
    end
  end
end
