defmodule Regents.Repo.Migrations.PatchbayOAuthLongValues do
  @moduledoc """
  Connected apps: every column an accepted request can fill past 255
  characters loses that limit (`RegentOAuth.Migration.V4`). The code's state
  and callback were widened by the migration before this one; this adds an
  app's name, the address of its keys and its list of callbacks.

  Widening only: no stored row changes, nothing is rewritten, dropped, renamed
  or narrowed.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    # RegentOAuth.Migration.V4.up/0 written out as regent_oauth holds it at
    # elixir-utils 6d98a113 (Patchbay da7b217b's pin), since this site does not
    # carry regent_oauth.
    alter table(:oauth_tokens) do
      modify(:state, :text)
      modify(:redirect_uri, :text)
    end

    alter table(:oauth_clients) do
      modify(:name, :text)
      modify(:redirect_uris, {:array, :varchar})
      modify(:jwks_uri, :text)
    end
  end

  def down, do: :ok
end
