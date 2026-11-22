defmodule Regents.Keyfleet.Dms.ReadMark do
  @moduledoc """
  How far one person has read one conversation on the site: the place of the
  last message its page showed them. A conversation whose last message is past
  it, and came from the other Key, has something they have not seen.

  A mark only ever moves forward, and only its own person sets it and reads
  it. It goes when its conversation is deleted.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Dms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "dm_read_marks"
    schema("keyfleet_app")
    repo(Regents.Repo)

    references do
      reference(:conversation, on_delete: :delete)
    end
  end

  actions do
    # Read up to `seq`; a mark already further along stays where it is.
    create :mark do
      accept [:conversation_id, :seq]
      change set_attribute(:human_account_id, actor(:human_account_id))
      upsert? true
      upsert_identity :one_per_conversation
      upsert_fields [:seq]
      upsert_condition expr(upsert_conflict(:seq) > seq)
      return_skipped_upsert? true
    end

    # The reader's own marks in the conversations named.
    read :in_conversations do
      argument :conversation_ids, {:array, :uuid}, allow_nil?: false

      filter expr(
               conversation_id in ^arg(:conversation_ids) and
                 human_account_id == ^actor(:human_account_id)
             )
    end
  end

  policies do
    policy action([:mark, :in_conversations]) do
      authorize_if actor_attribute_equals(:role, :human)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :human_account_id, :integer, allow_nil?: false, public?: true

    attribute :seq, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: @max_bigint]
  end

  relationships do
    belongs_to :conversation, Regents.Keyfleet.Dms.Conversation do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_conversation, [:human_account_id, :conversation_id]
  end
end
