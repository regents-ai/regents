defmodule Regents.Keyfleet.Rooms.ReadMark do
  @moduledoc """
  How far one person has read one of a fleet's rooms on the site: the place of
  the last line the room's page showed them, muted posts included. A room whose
  head is past it has something they have not seen.

  A mark only ever moves forward, and only its own person sets it and reads it.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "room_read_marks"
    schema("keyfleet_app")
    repo(Regents.Repo)

    references do
      reference(:room, on_delete: :delete)
    end
  end

  actions do
    # Read up to `seq`; a mark already further along stays where it is.
    create :mark do
      accept [:room_id, :seq]
      change set_attribute(:human_account_id, actor(:human_account_id))
      upsert? true
      upsert_identity :one_per_room
      upsert_fields [:seq]
      upsert_condition expr(upsert_conflict(:seq) > seq)
      return_skipped_upsert? true
    end

    # The reader's own marks in the rooms named.
    read :in_rooms do
      argument :room_ids, {:array, :uuid}, allow_nil?: false
      filter expr(room_id in ^arg(:room_ids) and human_account_id == ^actor(:human_account_id))
    end
  end

  policies do
    policy action([:mark, :in_rooms]) do
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
    belongs_to :room, Regents.Keyfleet.Rooms.Room do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_room, [:human_account_id, :room_id]
  end
end
