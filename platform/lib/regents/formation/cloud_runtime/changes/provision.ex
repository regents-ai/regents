defmodule Regents.Formation.CloudRuntime.Changes.Provision do
  use Ash.Resource.Change

  alias Regents.Actors.Human
  alias Regents.Formation
  alias Regents.Formation.SpriteProvider
  alias RegentSprites.{Error, Sprite}

  @impl true
  def change(changeset, _opts, %{actor: %Human{human_account_id: human_account_id} = actor}) do
    case Formation.get_my_regent(actor: actor) do
      {:ok, nil} ->
        Ash.Changeset.add_error(changeset,
          field: :regent_id,
          message: "requires a formed Regent"
        )

      {:ok, regent} ->
        sprite_name = "regent-" <> String.replace(regent.id, "-", "")

        changeset
        |> Ash.Changeset.force_change_attributes(%{
          human_account_id: human_account_id,
          regent_id: regent.id,
          sprite_name: sprite_name
        })
        |> Ash.Changeset.before_transaction(&provision_sprite(&1, sprite_name))

      {:error, _error} ->
        provider_error(changeset)
    end
  end

  def change(changeset, _opts, _context), do: changeset

  defp provision_sprite(changeset, sprite_name) do
    case create_or_get(sprite_name) do
      {:ok, %Sprite{name: ^sprite_name} = sprite} -> put_sprite(changeset, sprite)
      {:ok, %Sprite{}} -> provider_error(changeset)
      {:error, %Error{}} -> provider_error(changeset)
    end
  end

  # The name is fixed per Regent, so a name already in use is this Regent's Sprite.
  defp create_or_get(sprite_name) do
    case SpriteProvider.adapter().create(sprite_name, wait_for_capacity: false) do
      {:error, %Error{reason: {:sprites, 409, _message}}} ->
        SpriteProvider.adapter().get(sprite_name)

      result ->
        result
    end
  end

  defp put_sprite(changeset, sprite) do
    Ash.Changeset.force_change_attributes(changeset, %{
      provider_sprite_id: sprite.id,
      sprite_name: sprite.name,
      url: sprite.url,
      provider_status: sprite.status,
      observed_at: DateTime.utc_now()
    })
  end

  defp provider_error(changeset) do
    Ash.Changeset.add_error(changeset,
      field: :sprite_name,
      message: "could not verify the Sprite"
    )
  end
end
