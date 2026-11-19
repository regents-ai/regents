defmodule RegentPoints.Event do
  @moduledoc false
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "point_events"
    schema("regent_points")
    repo(&RegentPoints.repo/2)

    custom_indexes do
      index([:account_id, :processing_status])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :program_id, :string, allow_nil?: false
    attribute :source_app, :string, allow_nil?: false
    attribute :source_kind, :string, allow_nil?: false
    attribute :source_event_key, :string, allow_nil?: false
    attribute :rule_id, :string, allow_nil?: false
    attribute :account_id, :integer, allow_nil?: false
    attribute :actor_kind, :string, allow_nil?: false, constraints: [match: ~r/^(human|agent)$/]
    attribute :actor_id, :string, allow_nil?: false
    attribute :source_action_at, :utc_datetime_usec, allow_nil?: false
    attribute :qualified_at, :utc_datetime_usec, allow_nil?: false
    attribute :evidence_ref, :string, allow_nil?: false, sensitive?: true
    attribute :payload_digest, :string, allow_nil?: false
    attribute :evidence, :map, allow_nil?: false, sensitive?: true
    attribute :rule_snapshot, :map, allow_nil?: false
    attribute :award_key, :string, allow_nil?: false

    attribute :processing_status, :atom,
      default: :pending,
      allow_nil?: false,
      constraints: [one_of: [:pending, :confirmed, :capped, :rejected]]

    attribute :processed_at, :utc_datetime_usec
    attribute :reason_code, :string
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :account, RegentPoints.Account,
      define_attribute?: false,
      source_attribute: :account_id,
      attribute_type: :integer
  end

  actions do
    read :read do
      primary? true
    end

    create :record do
      accept [
        :program_id,
        :source_app,
        :source_kind,
        :source_event_key,
        :rule_id,
        :account_id,
        :actor_kind,
        :actor_id,
        :source_action_at,
        :qualified_at,
        :evidence_ref,
        :payload_digest,
        :evidence,
        :rule_snapshot,
        :award_key
      ]

      # A source whose event was rejected, so earned nothing, can be offered again:
      # the new offer's facts replace the refused ones and wait for their own award,
      # with the refusal's reason and time cleared. Any other event stands as it is.
      change set_attribute(:reason_code, nil)
      change set_attribute(:processed_at, nil)
      upsert? true
      upsert_identity :source_rule

      upsert_fields [
        :account_id,
        :actor_kind,
        :actor_id,
        :source_action_at,
        :qualified_at,
        :evidence_ref,
        :payload_digest,
        :evidence,
        :rule_snapshot,
        :processing_status,
        :reason_code,
        :processed_at
      ]

      upsert_condition expr(processing_status == :rejected)
      return_skipped_upsert? true
    end

    update :finish do
      accept [:processing_status, :reason_code]
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      forbid_if always()
    end
  end

  identities do
    identity :source_rule, [:program_id, :source_app, :source_kind, :source_event_key, :rule_id]
  end
end
