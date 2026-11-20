defmodule Regents.Repo.Migrations.TechtreeOAuthClientDocuments do
  @moduledoc """
  Published identities for connected apps, such as Claude's: an app that names
  itself by an HTTPS address is recorded as an ordinary client, and
  `RegentOAuth.Migration.V3` adds the one table that remembers which address
  each such client came from and when to read it again.

  Additive only: one new, empty table and its index, in this site's schema (its
  reference to `oauth_clients` names no schema of its own). Nothing existing
  changes.

  Hand-written; no resource changes shape. Up only, as the library's are.

  Carried into regents.sh with the library step written out here, exactly as
  regent_oauth held it at elixir-utils f42fc4fc (Techtree c6dba424's pin), since
  this repository does not carry regent_oauth.
  """

  use Ecto.Migration

  def up do
    execute "SET LOCAL lock_timeout = '5s'"

    # RegentOAuth.Migration.V3.up/0
    create table(:oauth_client_documents, primary_key: false) do
      add(:url, :text, primary_key: true)

      add(:client_id, references(:oauth_clients, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:refresh_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:oauth_client_documents, [:client_id]))
  end
end
