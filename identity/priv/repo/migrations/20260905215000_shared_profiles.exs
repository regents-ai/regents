defmodule RegentIdentity.Migrations.SharedProfiles do
  use Ecto.Migration

  def up do
    execute("CREATE SCHEMA regent_identity")

    create table(:profiles, prefix: "regent_identity", primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:app_id, :text, null: false)
      add(:privy_user_id, :text, null: false)
      add(:display_name, :text)
      add(:wallet_address, :text)
      add(:wallet_addresses, {:array, :text}, null: false, default: [])
      add(:x_subject, :text)
      add(:x_username, :text)
      add(:x_display_name, :text)
      add(:proof_issued_at, :bigint, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:profiles, [:app_id, :privy_user_id],
             prefix: "regent_identity",
             name: :profiles_privy_subject_index
           )

    create unique_index(:profiles, [:app_id, :x_subject],
             prefix: "regent_identity",
             name: :profiles_x_subject_owner_index
           )
  end

  def down do
    raise "Shared identity contains retained user data; restore a reviewed recovery copy instead."
  end
end
