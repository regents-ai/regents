defmodule Regents.Keyfleet.Proposals.Words do
  @moduledoc """
  A proposal's words, kept off the chain. The chain keeps only their
  fingerprint, the proposal's `content_hash`.

  The words are saved when someone proposes, before their wallet sends the
  proposal, so they are here when the chain reader records it. Writing them
  never waits on the transaction. Their fingerprint is worked out here from
  the words themselves, never taken from whoever sends them, so a fleet's
  words under a fingerprint are always the words that fingerprint names. A
  proposal is shown with the words its fleet saved under its `content_hash`,
  and with none when nobody saved them.

  The same words saved again keep the first save. Anyone may read them. A
  person or an agent may save them only so often
  (`Regents.Keyfleet.Proposals.Changes.LimitWords`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Proposals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "proposal_words"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:content_hash, "proposal_words_content_hash_shape",
        check: "content_hash ~ '^0x[0-9a-f]{64}$'"
      )

      # As much as a proposal's text may be, in bytes.
      check_constraint(:text, "proposal_words_text_bytes",
        check: "octet_length(text) BETWEEN 1 AND 4000"
      )
    end
  end

  actions do
    defaults [:read]

    create :write do
      accept [:fleet_id, :text]
      upsert? true
      upsert_identity :one_per_fingerprint
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
      change Regents.Keyfleet.Proposals.Changes.Fingerprint
      change Regents.Keyfleet.Proposals.Changes.LimitWords
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
    end
  end

  # Words are saved by a signed-in person or agent, the ones who propose.
  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:write) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if Regents.Keyfleet.Checks.AgentActor
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :content_hash, :string,
      allow_nil?: false,
      writable?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]

    attribute :text, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false, allow_empty?: false]

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_fingerprint, [:fleet_id, :content_hash]
  end
end
