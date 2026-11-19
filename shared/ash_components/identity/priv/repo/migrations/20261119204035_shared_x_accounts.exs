defmodule RegentIdentity.Migrations.SharedXAccounts do
  @moduledoc """
  Several profiles in one app may hold the same X account, so `x_subject` has
  no unique index. No read finds a profile by its X account, so no index takes
  its place. The way back rebuilds the unique index, and fails while two
  profiles in one app hold the same X account.
  """

  use Ecto.Migration

  # The table is shared by every site, so neither way waits long for its lock.
  def up do
    execute("SET LOCAL lock_timeout = '5s'")
    drop(index())
  end

  def down do
    execute("SET LOCAL lock_timeout = '5s'")
    create(index())
  end

  defp index do
    unique_index(:profiles, [:app_id, :x_subject],
      prefix: "regent_identity",
      name: :profiles_x_subject_owner_index
    )
  end
end
