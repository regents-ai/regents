defmodule AshPlatform.Formation.CloudRuntime.Changes.RefreshStatus do
  use Ash.Resource.Change

  alias AshPlatform.Formation.SpriteProvider

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      sprite_name = changeset.data.sprite_name

      case SpriteProvider.adapter().get(sprite_name) do
        {:ok, %{sprite_name: ^sprite_name} = sprite} ->
          Ash.Changeset.force_change_attributes(changeset, %{
            provider_sprite_id: sprite.provider_sprite_id,
            url: sprite.url,
            provider_status: sprite.provider_status,
            observed_at: DateTime.utc_now()
          })

        _result ->
          Ash.Changeset.add_error(changeset,
            field: :sprite_name,
            message: "could not refresh the Sprite"
          )
      end
    end)
  end
end
