defmodule Regents.Formation.SpriteProvider do
  @moduledoc false

  @callback create(String.t(), keyword()) ::
              {:ok, RegentSprites.Sprite.t()} | {:error, RegentSprites.Error.t()}
  @callback get(String.t()) :: {:ok, RegentSprites.Sprite.t()} | {:error, RegentSprites.Error.t()}

  def adapter do
    Application.fetch_env!(:regents, :sprite_provider)
  end
end
