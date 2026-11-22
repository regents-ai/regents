defmodule Regents.Repo.Migrations.KeyfleetUsageMeter do
  @moduledoc """
  Each fleet's usage, one calendar month at a time (`Keyfleet.Usage.Month`).
  A new, empty table; nothing that exists changes.
  """

  use Ecto.Migration

  def up do
    create table(:fleet_usage, primary_key: false) do
      add(:fleet_id, :text, null: false, primary_key: true)
      add(:month, :date, null: false, primary_key: true)
      add(:workspace_bytes, :bigint, null: false)
      add(:workspace_items, :bigint, null: false)
      add(:chat_posts, :bigint, null: false)
      add(:chat_bytes, :bigint, null: false)
      add(:counted_at, :utc_datetime_usec, null: false)
    end

    create constraint(:fleet_usage, :fleet_usage_month_start,
             check: """
               extract(day FROM month) = 1
             """
           )
  end

  def down do
    drop_if_exists(constraint(:fleet_usage, :fleet_usage_month_start))

    drop(table(:fleet_usage))
  end
end
