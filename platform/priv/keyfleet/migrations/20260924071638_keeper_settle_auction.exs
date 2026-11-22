defmodule Regents.Repo.Migrations.KeyfleetKeeperSettleAuction do
  @moduledoc """
  Lets the keeper record a strategy's `migrate(auction)`, which settles a
  fleet's auction once it has ended. Generated with `mix ash.codegen`.
  """

  use Ecto.Migration

  def up do
    drop_if_exists(constraint(:keeper_txs, :keeper_txs_function))

    create constraint(:keeper_txs, :keeper_txs_function,
             check: """
               function IN ('collect', 'migrate', 'recognize_surplus', 'recognize_surplus_revenue', 'release', 'request_reveal', 'send_protocol_share', 'sweep', 'sync_launch')
             """
           )
  end

  def down do
    drop_if_exists(constraint(:keeper_txs, :keeper_txs_function))

    create constraint(:keeper_txs, :keeper_txs_function,
             check: """
               function IN ('collect', 'recognize_surplus', 'recognize_surplus_revenue', 'release', 'request_reveal', 'send_protocol_share', 'sweep', 'sync_launch')
             """
           )
  end
end
