defmodule Regents.Repo.Migrations.KeyfleetEpochs do
  @moduledoc """
  Numbers ownership epochs from 1, as the contract does: the mint is epoch 1
  and every transfer adds one.

  Generated with `mix ash.codegen epochs`. Adding each check reads the rows
  already written, so the migration stops if any key or pairing holds epoch 0.
  """

  use Ecto.Migration

  def up do
    drop_if_exists(constraint(:key_attachments, :key_attachments_nonnegative_epoch))

    create constraint(:key_attachments, :key_attachments_positive_epoch,
             check: """
               ownership_epoch >= 1
             """
           )

    drop_if_exists(constraint(:key_pairings, :key_pairings_nonnegative_epoch))

    create constraint(:key_pairings, :key_pairings_positive_epoch,
             check: """
               ownership_epoch >= 1
             """
           )
  end

  def down do
    drop_if_exists(constraint(:key_pairings, :key_pairings_positive_epoch))

    create constraint(:key_pairings, :key_pairings_nonnegative_epoch,
             check: """
               ownership_epoch >= 0
             """
           )

    drop_if_exists(constraint(:key_attachments, :key_attachments_positive_epoch))

    create constraint(:key_attachments, :key_attachments_nonnegative_epoch,
             check: """
               ownership_epoch >= 0
             """
           )
  end
end
