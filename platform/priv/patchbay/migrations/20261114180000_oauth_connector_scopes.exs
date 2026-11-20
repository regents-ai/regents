defmodule Regents.Repo.Migrations.PatchbayOAuthConnectorScopes do
  @moduledoc """
  patchbay.help's own sign-in for connected apps (`Patchbay.OAuth`, `:main`)
  offers asking and replying (`patchbay.posts.write`) beside the identity
  permission. Apps are one table for both addresses, so every app already
  recorded may be offered every permission either address has
  (`RegentOAuth.Migration.ClientScopes`); each address still grants only its
  own, and only with the person's consent.

  Additive only: it inserts the scope rows and app links that are missing and
  changes nothing already there.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    # RegentOAuth.Migration.ClientScopes.up/1 for these three names, written out
    # as regent_oauth holds it at elixir-utils 6d98a113 (Patchbay da7b217b's pin),
    # since this site does not carry regent_oauth.
    table = fn name -> ~s("#{prefix()}".#{name}) end

    names =
      "ARRAY['patchbay.events.read', 'regent.identity.manage', 'patchbay.posts.write']::varchar[]"

    execute("""
    INSERT INTO #{table.("oauth_scopes")} (id, name, public, inserted_at, updated_at)
    SELECT gen_random_uuid(), name, false, now(), now() FROM unnest(#{names}) AS name
    ON CONFLICT (name) DO NOTHING
    """)

    execute("""
    INSERT INTO #{table.("oauth_clients_scopes")} (client_id, scope_id)
    SELECT client.id, scope.id
    FROM #{table.("oauth_clients")} AS client
    JOIN #{table.("oauth_scopes")} AS scope ON scope.name = ANY(#{names})
    WHERE client.confidential = false AND client.pkce = true
    ON CONFLICT (client_id, scope_id) DO NOTHING
    """)
  end
end
