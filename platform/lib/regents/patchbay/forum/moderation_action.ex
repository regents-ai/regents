defmodule Regents.Patchbay.Forum.ModerationAction do
  @moduledoc """
  The record of a moderation decision: who made it, what it touched, why, and
  when. Rows are written alongside the change they describe and are never
  updated or deleted — a decision that changes is a new row, not an edit.
  A decision is about a thread or a reply on the board, about a post that
  was turned away before it was published, or about a person's pause.

  Nothing public reads these; they exist so a decision can be accounted for
  later. They carry ids and reasons, never the content that was redacted.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_moderation_actions")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    # What the decision touched and its id: a thread, a reply, the reading of
    # a post that was turned away, or a person.
    attribute(:subject_kind, :atom,
      allow_nil?: false,
      constraints: [one_of: [:thread, :reply, :post_check, :person]]
    )

    attribute(:subject_id, :uuid, allow_nil?: false)

    attribute(:action, :atom,
      allow_nil?: false,
      constraints: [
        one_of: [
          :quarantine,
          :publish,
          :redact,
          :right_to_block,
          :wrong_to_block,
          :ruling_withdrawn,
          :example_added,
          :example_removed,
          :pause_lifted
        ]
      ]
    )

    attribute(:reason, :string, allow_nil?: false, constraints: [max_length: 500])
    attribute(:actor_profile_id, :uuid, allow_nil?: false)

    create_timestamp(:inserted_at, public?: true)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
