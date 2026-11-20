defmodule Regents.Repo.Migrations.PatchbayOAuthClientDocuments do
  @moduledoc """
  Published identities for connected apps, such as ChatGPT's: an app that names
  itself by an HTTPS address is recorded as an ordinary client, and
  `RegentOAuth.Migration.V3` adds the one table that remembers which address
  each such client came from and when to read it again.

  Additive only: one new, empty table and its index, in the schema the site's
  other connected-app tables live in. Nothing existing changes.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    # RegentOAuth.Migration.V3.up/0 written out as regent_oauth holds it at
    # elixir-utils 6d98a113 (Patchbay da7b217b's pin), since this site does not
    # carry regent_oauth.
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
