defmodule Regents.TestSpriteProvider do
  @behaviour Regents.Formation.SpriteProvider

  @impl true
  def create(sprite_name, opts) do
    capture({:sprite_create, sprite_name, opts})
    Process.get(:test_sprite_create_result, {:ok, sprite(sprite_name, "cold")})
  end

  @impl true
  def get(sprite_name) do
    capture({:sprite_get, sprite_name})
    Process.get(:test_sprite_get_result, {:ok, sprite(sprite_name, "cold")})
  end

  defp capture(message) do
    if Process.get(:capture_sprite_provider_calls, false), do: send(self(), message)
  end

  defp sprite(sprite_name, status) do
    provider_id = :crypto.hash(:sha256, sprite_name) |> Base.encode16(case: :lower)

    %RegentSprites.Sprite{
      id: "sprite-" <> binary_part(provider_id, 0, 24),
      name: sprite_name,
      url: "https://#{sprite_name}.sprites.app",
      status: status
    }
  end
end
