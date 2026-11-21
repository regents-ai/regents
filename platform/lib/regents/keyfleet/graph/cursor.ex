defmodule Regents.Keyfleet.Graph.Cursor do
  @moduledoc """
  How far one fleet's graph log has been copied into the read tables, and
  from which run of that log.

  The read tables hang off this row: removing it removes every event, object
  and relation copied for the fleet, and the copy then
  starts again from the beginning of the log. Only the projector writes here; anyone may read.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Graph,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "graph_cursors"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:applied_seq, "graph_cursors_nonnegative_applied_seq",
        check: "applied_seq >= 0"
      )
    end
  end

  actions do
    defaults [:read]

    # The fleet's cursor, held until the transaction ends: each page the
    # projector copies and each project's deletion take their turn on it.
    read :hold do
      public? false
      get_by [:fleet_id]
      prepare build(lock: :for_update)
    end

    create :start do
      public? false
      accept [:fleet_id, :run_id]
      change set_attribute(:applied_seq, 0)
    end

    # Moves the cursor on only from where this copy found it. When another
    # copy has moved it meanwhile, this one fails, and the page it copied
    # rolls back with it.
    update :advance do
      public? false
      accept [:applied_seq]
      require_attributes [:applied_seq]
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.filter(changeset, expr(applied_seq == ^changeset.data.applied_seq))
      end
    end

    destroy :forget do
      public? false
    end

    # The Atlas has counted the copied log as far as `counted_seq`
    # (`Regents.Keyfleet.Atlas.Count`).
    update :counted do
      public? false
      accept [:counted_seq]
    end

    # The cursors whose copied log the Atlas has not counted to the end
    # (`Regents.Keyfleet.Atlas.Fill`).
    read :uncounted do
      public? false
      filter expr(counted_seq < applied_seq)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action([:start, :advance, :forget, :counted]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :run_id, :string, allow_nil?: false, public?: true, constraints: [trim?: false]

    # The last place in the log copied, counting every event, including the
    # ones the read tables leave out.
    attribute :applied_seq, :integer, allow_nil?: false, public?: true, constraints: [min: 0]

    # How far into the copied log the Atlas has counted: every change at or
    # before it is in the Atlas's buckets, and none after. A log copied again
    # from the beginning starts it again from nothing.
    attribute :counted_seq, :integer,
      allow_nil?: false,
      public?: true,
      default: 0,
      constraints: [min: 0]
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      primary_key? true
      allow_nil? false
      public? true
    end
  end
end
