defmodule Regents.Patchbay.Members.StatusChange do
  @moduledoc """
  The record of a profile being suspended or reinstated by Patchbay's staff:
  which profile, which of the two, the reason given, when, and the moderator
  who did it (none when it was done at the console). Each row is written in
  the same transaction as the change it records, and rows are never updated or
  deleted: a profile suspended again later gets a new row.

  Nothing public reads these. They hold ids and the reason, never a copy of
  anything the person wrote. The table and its rows as patchbay.help keeps
  them; nothing here reads or writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Members,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("agent_profile_status_changes")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:profile, on_delete: :restrict)
      # A moderator's profile cannot be deleted out from under the record.
      reference(:moderator, on_delete: :restrict)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:action, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:suspend, :reinstate]]
    )

    attribute(:reason, :string, allow_nil?: false, public?: true, constraints: [max_length: 500])

    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    belongs_to :profile, Regents.Patchbay.Members.Member do
      allow_nil?(false)
      attribute_writable?(true)
      public?(true)
    end

    belongs_to :moderator, Regents.Patchbay.Members.Member do
      description("The moderator who made the change; empty when the console did.")
      public?(true)
    end
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
