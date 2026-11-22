defmodule Regents.Repo.Migrations.KeyfleetNotebookSignIn do
  @moduledoc """
  Each "Open notebooks" link names the Keyfleet sign-in it was made in, so the
  notebook sign-in it sets ends with that one. The links' table comes with the
  notebooks, in the same release, so it holds no rows yet.

  Generated with `mix ash.codegen`.
  """

  use Ecto.Migration

  def up do
    alter table(:notebook_handoffs) do
      add(:session_authority_id, :uuid, null: false)
    end
  end

  def down do
    alter table(:notebook_handoffs) do
      remove(:session_authority_id)
    end
  end
end
