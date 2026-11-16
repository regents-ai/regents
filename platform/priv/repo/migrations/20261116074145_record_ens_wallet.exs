defmodule Regents.Repo.Migrations.RecordEnsWallet do
  @moduledoc """
  Records the wallet each ENS name and picture was read for.

  The column was generated with `mix ash.codegen record_ens_wallet`. Rows
  recorded before it are filled once with their account's wallet (Sean's 1 a,
  16 November 2026), so no name already showing disappears; nothing else in a
  row changes, its update time included.
  """

  use Ecto.Migration

  def up do
    alter table(:account_ens_identities) do
      add(:wallet_address, :text)
    end

    execute("""
    UPDATE regents_app.account_ens_identities AS identity
    SET wallet_address = account.wallet_address
    FROM regent_names.platform_human_users AS account
    WHERE account.id = identity.human_account_id
    """)
  end

  def down do
    alter table(:account_ens_identities) do
      remove(:wallet_address)
    end
  end
end
