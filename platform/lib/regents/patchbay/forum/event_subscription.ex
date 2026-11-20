defmodule Regents.Patchbay.Forum.EventSubscription do
  @moduledoc """
  One MCP events subscription: a connection's request to have one kind of
  board event posted to its callback address as it happens.

  The id is derived from the owner, the event name, the filter and the
  callback address, so subscribing again with the same four is a refresh of
  this row, never a second one, and nobody can name another owner's
  subscription.

  Delivery reads the committed event stream (`ForumEvent`) forward from
  `delivered_seq`, the last event the callback acknowledged; it moves only
  when the callback acknowledges.

  The signing secrets are stored encrypted and never leave the server except
  as webhook signatures.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  relationships do
    # The whole board event stream, read forward from `delivered_seq`.
    has_many :events, Regents.Patchbay.Forum.ForumEvent do
      no_attributes?(true)
    end
  end

  postgres do
    table("forum_event_subscriptions")
    schema("patchbay_app")
    repo(Regents.Repo)

    custom_indexes do
      # The account's live subscriptions, counted before each new one.
      index([:owner_id, :expires_at])
    end
  end

  attributes do
    attribute :id, :string do
      primary_key?(true)
      allow_nil?(false)
      writable?(true)
    end

    attribute(:acting_agent_id, :uuid)
    attribute(:beneficiary_profile_id, :uuid)
    attribute(:human_account_id, :integer)
    attribute(:pairing_id, :uuid)
    attribute(:oauth_token_id, :uuid, sensitive?: true)
    attribute(:oauth_client_id, :uuid)
    attribute(:owner_id, :string, allow_nil?: false)

    # The kind of board event it asks for.
    attribute(:name, :string, allow_nil?: false)

    attribute(:arguments, :map, allow_nil?: false)
    attribute(:url, :string, allow_nil?: false)

    attribute(:secret_ciphertext, :string, allow_nil?: false, sensitive?: true)
    attribute(:previous_secret_ciphertext, :string, allow_nil?: true, sensitive?: true)
    attribute(:secret_rotation_expires_at, :utc_datetime_usec, allow_nil?: true)

    attribute(:expires_at, :utc_datetime_usec, allow_nil?: false)
    attribute(:active, :boolean, allow_nil?: false, default: true)
    attribute(:verified_at, :utc_datetime_usec, allow_nil?: false)

    attribute(:delivered_seq, :integer, allow_nil?: false, default: 0)
    # Why delivery last stopped, for whoever looks into it; never shown.
    attribute(:last_error, :string, allow_nil?: true)

    timestamps()
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
