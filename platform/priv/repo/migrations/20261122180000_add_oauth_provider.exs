defmodule Regents.Repo.Migrations.AddOAuthProvider do
  @moduledoc """
  The connected-app OAuth tables (`oauth_*`) in `regents_app`, at the provider's
  current version: `RegentOAuth.Migration` creates the core tables, `V2` keeps
  only hashed access and refresh tokens, and `V3` records published HTTPS client
  documents. Additive only; nothing existing changes.
  """

  use Ecto.Migration

  def up do
    execute "SET LOCAL lock_timeout = '5s'"

    RegentOAuth.Migration.up()
    RegentOAuth.Migration.V2.up()
    RegentOAuth.Migration.V3.up()
  end
end
