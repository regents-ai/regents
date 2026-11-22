defmodule Regents.Repo.Migrations.KeyfleetMentions do
  @moduledoc """
  The Keys each post mentions (`Keyfleet.Rooms.Mentions`). Posts written
  before keep the empty default and are not read again: a constant default
  is only recorded, so no row is rewritten. Nothing that exists changes.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:messages) do
      add(:mentions, {:array, :bigint}, null: false, default: [])
    end
  end

  def down do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:messages) do
      remove(:mentions)
    end
  end
end
