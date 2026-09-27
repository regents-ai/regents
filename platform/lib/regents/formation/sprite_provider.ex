defmodule Regents.Formation.SpriteProvider do
  @moduledoc false

  @type sprite :: %{
          required(:provider_sprite_id) => String.t(),
          required(:sprite_name) => String.t(),
          required(:url) => String.t(),
          required(:provider_status) => String.t()
        }

  @callback create(String.t()) :: {:ok, sprite()} | {:error, term()}
  @callback get(String.t()) :: {:ok, sprite()} | {:error, term()}

  def adapter do
    Application.fetch_env!(:regents, :sprite_provider)
  end
end
