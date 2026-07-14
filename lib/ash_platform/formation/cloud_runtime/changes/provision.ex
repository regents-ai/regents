defmodule AshPlatform.Formation.CloudRuntime.Changes.Provision do
  use Ash.Resource.Change

  alias AshPlatform.Actors.Human
  alias AshPlatform.Formation
  alias AshPlatform.Formation.SpriteProvider

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
        |> Ash.Changeset.before_transaction(fn changeset ->
          case SpriteProvider.adapter().create(sprite_name) do
            {:ok, %{sprite_name: ^sprite_name} = sprite} -> put_sprite(changeset, sprite)
            {:ok, _wrong_sprite} -> provider_error(changeset)
            {:error, _reason} -> provider_error(changeset)
          end
        end)

      {:error, _error} ->
        provider_error(changeset)
    end
  end

  def change(changeset, _opts, _context), do: changeset

  defp put_sprite(changeset, sprite) do
    Ash.Changeset.force_change_attributes(changeset, %{
      provider_sprite_id: sprite.provider_sprite_id,
      sprite_name: sprite.sprite_name,
      url: sprite.url,
      provider_status: sprite.provider_status,
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
