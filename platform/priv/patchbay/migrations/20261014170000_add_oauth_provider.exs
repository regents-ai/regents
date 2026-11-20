defmodule Regents.Repo.Migrations.PatchbayAddOAuthProvider do
  use Ecto.Migration

  # RegentOAuth.Migration.up/0 written out as regent_oauth holds it at
  # elixir-utils 6d98a113 (Patchbay da7b217b's pin), since this site does not
  # carry regent_oauth.
  def up do
    create table(:oauth_clients, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string, null: false, default: "")
      add(:secret, :string, null: false)
      add(:confidential, :boolean, null: false, default: false)
      add(:authorize_scope, :boolean, null: false, default: false)
      add(:redirect_uris, {:array, :string}, null: false, default: [])
      add(:supported_grant_types, {:array, :string}, null: false, default: [])
      add(:pkce, :boolean, null: false, default: false)
      add(:public_refresh_token, :boolean, null: false, default: false)
      add(:public_revoke, :boolean, null: false, default: false)
      add(:authorization_code_ttl, :integer, null: false)
      add(:access_token_ttl, :integer, null: false)
      add(:refresh_token_ttl, :integer, null: false)
      add(:id_token_ttl, :integer, null: false)
      add(:id_token_signature_alg, :string, null: false, default: "RS512")
      add(:id_token_kid, :string)
      add(:public_key, :text)
      add(:private_key, :text)
      add(:token_endpoint_auth_methods, {:array, :string}, null: false, default: [])
      add(:token_endpoint_jwt_auth_alg, :string, default: "HS256")
      add(:jwt_public_key, :text)
      add(:jwks_uri, :string)
      add(:userinfo_signed_response_alg, :string)
      add(:logo_uri, :string)
      add(:metadata, :map, null: false, default: %{})
      add(:trusted_authorities, :text, null: false, default: "")
      add(:trusted_hosts, {:array, :string}, null: false, default: [])
      timestamps()
    end

    create table(:oauth_scopes, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string, null: false, default: "")
      add(:label, :string)
      add(:public, :boolean, null: false, default: false)
      timestamps()
    end

    create(unique_index(:oauth_scopes, [:name]))

    create table(:oauth_clients_scopes) do
      add(:client_id, references(:oauth_clients, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:scope_id, references(:oauth_scopes, type: :uuid, on_delete: :delete_all), null: false)
    end

    create(unique_index(:oauth_clients_scopes, [:client_id, :scope_id]))

    create table(:oauth_tokens, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:type, :string, null: false)
      add(:value, :string, null: false)
      # Written for each code and token as it is issued, from the running
      # site's configuration (`RegentOAuth.bind/2`); a row without them is
      # refused.
      add(:oauth_issuer, :text)
      add(:mcp_resource, :text)
      add(:refresh_token, :string)
      add(:previous_token, :string)
      add(:previous_code, :string)
      add(:state, :string)
      add(:nonce, :string)
      add(:scope, :string, null: false, default: "")
      add(:redirect_uri, :string)
      add(:expires_at, :bigint, null: false)
      add(:revoked_at, :utc_datetime_usec)
      add(:refresh_token_revoked_at, :utc_datetime_usec)
      add(:code_challenge_hash, :string)
      add(:code_challenge_method, :string)

      add(:client_id, references(:oauth_clients, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:sub, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:oauth_tokens, [:value]))
    create(unique_index(:oauth_tokens, [:refresh_token]))
    create(index(:oauth_tokens, [:sub, :client_id]))
  end
end
