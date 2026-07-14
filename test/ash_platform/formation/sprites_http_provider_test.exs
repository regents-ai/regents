defmodule AshPlatform.Formation.SpritesHttpProviderTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Formation.SpritesHttpProvider

  setup do
    previous_sprites = Application.fetch_env!(:ash_platform, :sprites)
    previous_req_options = Application.get_env(:ash_platform, :sprites_req_options)

    Application.put_env(:ash_platform, :sprites,
      base_url: "https://api.sprites.dev",
      token: "test-provider-token"
    )

    Application.put_env(:ash_platform, :sprites_req_options, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.put_env(:ash_platform, :sprites, previous_sprites)

      if previous_req_options do
        Application.put_env(:ash_platform, :sprites_req_options, previous_req_options)
      else
        Application.delete_env(:ash_platform, :sprites_req_options)
      end
    end)

    :ok
  end

  test "create sends the documented private Sprite request and normalizes verified facts" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/sprites"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-provider-token"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "name" => "regent-abc123",
               "url_settings" => %{"auth" => "sprite"},
               "wait_for_capacity" => false
             }

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(sprite_body("regent-abc123", "cold"))
    end)

    assert {:ok, sprite} = SpritesHttpProvider.create("regent-abc123")
    assert sprite.sprite_name == "regent-abc123"
    assert sprite.provider_status == "cold"
    refute inspect(sprite) =~ "test-provider-token"
  end

  test "a create conflict reconciles only through the deterministic Sprite GET" do
    Req.Test.stub(__MODULE__, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/sprites"} ->
          Plug.Conn.send_resp(conn, 400, "{}")

        {"GET", "/v1/sprites/regent-existing"} ->
          Req.Test.json(conn, sprite_body("regent-existing", "running"))
      end
    end)

    assert {:ok, %{sprite_name: "regent-existing", provider_status: "running"}} =
             SpritesHttpProvider.create("regent-existing")
  end

  test "malformed responses and missing configuration fail closed" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"id" => "sprite-id", "name" => "regent-invalid", "status" => "cold"})
    end)

    assert {:error, :invalid_provider_response} =
             SpritesHttpProvider.create("regent-invalid")

    Application.put_env(:ash_platform, :sprites,
      base_url: "https://api.sprites.dev",
      token: nil
    )

    assert {:error, :not_configured} = SpritesHttpProvider.get("regent-abc123")
  end

  defp sprite_body(name, status) do
    %{
      "id" => "sprite-provider-id",
      "name" => name,
      "url" => "https://#{name}.sprites.app",
      "status" => status
    }
  end
end
