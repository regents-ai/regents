defmodule Regents.Repo.Migrations.AddOAuthConnector do
  @moduledoc """
  The Claude connector's sign-in tables, at the provider's current version:
  `RegentOAuth.Migration` creates the `oauth_*` tables in `regents_app`, then
  `RegentOAuth.Migration.V2` keeps only the SHA-256 hash of each access and
  refresh token. Both are additive here: the tables are new, so V2's rewrite
  meets no rows.

  Neither needs the site's address: each code and token gets this site's issuer
  and resource written on it as it is issued.

  Going back drops the four tables, and with them every app connected since.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    RegentOAuth.Migration.up()
    RegentOAuth.Migration.V2.up()
  end

  def down do
    drop table(:oauth_tokens)
    drop table(:oauth_clients_scopes)
    drop table(:oauth_scopes)
    drop table(:oauth_clients)
  end
end
