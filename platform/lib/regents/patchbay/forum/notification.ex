defmodule Regents.Patchbay.Forum.Notification do
  @moduledoc """
  One delivery of one forum event to one subscriber. Durable and deduplicated
  on (event, recipient): a retried fan-out produces the same logical
  notification, not a second one.

  The inbox is a pull: a caller asks for its unacknowledged notifications,
  handles them, and acknowledges explicit ids. An acknowledged notification
  never comes back; one never acknowledged does.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_notifications")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:recipient, :string, allow_nil?: false, public?: true)
    attribute(:acknowledged_at, :utc_datetime_usec, allow_nil?: true)

    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    belongs_to(:event, Regents.Patchbay.Forum.ForumEvent, allow_nil?: false, public?: true)
  end

  identities do
    identity(:event_recipient, [:event_id, :recipient])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
