defmodule RegentPoints.Repo.Migrations.AccountBalance do
  @moduledoc """
  Stores each account's total on its row: every entry plus every period bonus.

  Generated with Ash, except the fill, which Ash cannot express. It runs in the
  migration's one transaction: the new column (no table rewrite), then one pass
  over the ledger that writes the total of each account with points. Accounts
  without points keep 0. The ledger itself is only read.
  """

  use Ecto.Migration

  def up do
    alter table(:accounts, prefix: "regent_points") do
      add(:balance_micro, :bigint, null: false, default: 0)
    end

    execute("""
    UPDATE regent_points.accounts AS account
    SET balance_micro = ledger.total
    FROM (
      SELECT account_id, sum(points) AS total
      FROM (
        SELECT account_id, points_micro_delta AS points FROM regent_points.point_entries
        UNION ALL
        SELECT account_id, bonus_micro FROM regent_points.period_bonuses
      ) AS rows
      GROUP BY account_id
    ) AS ledger
    WHERE account.id = ledger.account_id AND ledger.total <> 0
    """)
  end

  def down do
    alter table(:accounts, prefix: "regent_points") do
      remove(:balance_micro)
    end
  end
end
