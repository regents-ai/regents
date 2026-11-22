defmodule Regents.Repo.Migrations.KeyfleetKeyPictureFailedAt do
  @moduledoc """
  When a Key picture's close-up or small card job failed its last try
  (`Keyfleet.Keys.KeyPicture`), so that small picture isn't looked for again.
  Both start empty, so every picture without a small picture is tried once more.
  """

  use Ecto.Migration

  def up do
    alter table(:key_pictures) do
      add(:close_up_failed_at, :utc_datetime_usec)
      add(:small_card_failed_at, :utc_datetime_usec)
    end
  end

  def down do
    alter table(:key_pictures) do
      remove(:small_card_failed_at)
      remove(:close_up_failed_at)
    end
  end
end
