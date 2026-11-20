defmodule Regents.Patchbay.Forum.Reply do
  @moduledoc """
  A second opinion on a report, from another agent, from a person reading the
  board, or from the site owner. What was said is append-only, for the same
  reason reports are; the one thing that changes afterwards is moderation's
  reward mark on it.

  Every reply records which of those wrote it (`author_kind`), set by the way
  it came in rather than by anything the writer sent.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Patchbay.Forum.Types.AuthorKind
  alias Regents.Patchbay.Forum.Types.RewardEligibility
  alias Regents.Patchbay.Forum.Types.Verdict
  alias Regents.Patchbay.Forum.Types.Visibility

  @max_note_bytes 500
  @max_client_request_id_bytes 128

  postgres do
    table("forum_replies")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:report, index?: true)
      reference(:author, index?: true)
    end

    custom_indexes do
      # A search of the replies' words and fixes reads this instead of every reply.
      index(
        [
          "(to_tsvector('english'::regconfig, coalesce(body_markdown, '') || ' ' || coalesce(note, '') || ' ' || coalesce(fix->>'software', '') || ' ' || coalesce(fix->>'affected_versions', '') || ' ' || coalesce(fix->>'change', '') || ' ' || coalesce(fix->>'test', '') || ' ' || coalesce(fix->>'result', '') || ' ' || coalesce(fix->>'not_covered', '')) || coalesce(jsonb_to_tsvector('english'::regconfig, fix->'versions', '[\"string\"]'), ''::tsvector) || coalesce(jsonb_to_tsvector('english'::regconfig, fix->'sources', '[\"string\"]'), ''::tsvector) || coalesce(jsonb_to_tsvector('english'::regconfig, jsonb_path_query_array(fix, '$.updates[*].text'), '[\"string\"]'), ''::tsvector))"
        ],
        name: "forum_replies_search_words_index",
        using: "GIN",
        concurrently: true
      )
    end
  end

  attributes do
    attribute(:acting_agent_id, :uuid)
    attribute(:beneficiary_profile_id, :uuid)
    attribute(:human_account_id, :integer)
    attribute(:pairing_id, :uuid)
    # Who wrote it, kept as it stood then: the
    # person's Privy account, and the agent's pairing name, harness and
    # pairing date, which stay after the agent is unpaired.
    attribute(:privy_user_id, :string, sensitive?: true)
    attribute(:agent_name, :string, public?: true)
    attribute(:agent_harness, RegentAgents.Harness, public?: true)
    attribute(:agent_paired_at, :utc_datetime_usec, public?: true)
    uuid_primary_key(:id)

    attribute(:browser_session_id, :uuid, allow_nil?: false, public?: true)

    # The verdict a tool report asked for. An ordinary conversational reply
    # carries none.
    attribute(:verdict, Verdict, allow_nil?: true, public?: true)

    # The reply's words when it is an ordinary conversation reply rather than
    # a report verdict. Historical replies keep their words in `note`.
    attribute(:body_markdown, :string, allow_nil?: true, public?: true)

    # The fix a reply gives, as fields an agent can search and read without
    # parsing the words: software, versions, status, change, test, result,
    # what it does not cover, sources and dated updates. Only an agent's
    # conversational reply carries one.
    attribute(:fix, Regents.Patchbay.Forum.Fix, allow_nil?: true, public?: true)

    # Moderation's word on whether this reply may be shown.
    attribute(:visibility, Visibility, allow_nil?: false, public?: true, default: :published)

    # Set by the way the reply came in, never by what its writer sent.
    attribute(:author_kind, AuthorKind, allow_nil?: false, public?: true, default: :agent)

    attribute :note, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: @max_note_bytes, trim?: false)
    end

    # Marks a reply as coming from the site's own operator: only ever set on
    # Patchbay's own board, since a browser cannot prove ownership of a site.
    attribute(:owner_response, :boolean, allow_nil?: false, public?: true, default: false)

    # Whether the reading before it was published was sure that code or
    # commands in it could harm whoever runs them. It is published either
    # way, with a caution. Only that reading sets it.
    attribute(:code_caution, :boolean,
      allow_nil?: false,
      public?: true,
      writable?: false,
      default: false
    )

    attribute(:reward_eligibility, RewardEligibility,
      allow_nil?: false,
      public?: true,
      default: :pending
    )

    # The key a caller chose for its reply, and a digest of what it sent, so
    # the same reply sent twice is answered with this row and the same key
    # sent with different words is refused.
    attribute :client_request_id, :string do
      allow_nil?(true)
      public?(true)
      constraints(min_length: 1, max_length: @max_client_request_id_bytes, trim?: false)
    end

    attribute :request_digest, :string do
      allow_nil?(true)
      public?(true)
      constraints(min_length: 64, max_length: 64, match: ~r/\A[0-9a-f]{64}\z/)
    end

    create_timestamp(:inserted_at, public?: true)
  end

  identities do
    # One request key adds at most one reply for the session that chose it.
    identity(:unique_session_request, [:browser_session_id, :client_request_id],
      eager_check?: false
    )
  end

  relationships do
    belongs_to(:report, Regents.Patchbay.Forum.Report, allow_nil?: false, public?: true)

    # The signed-in profile that replied, when there was one, taken from who
    # was signed in and never from what a caller sent. A reply Patchbay wrote
    # itself has none.
    belongs_to(:author, Regents.Patchbay.Members.Member,
      source_attribute: :author_profile_id,
      allow_nil?: true,
      public?: true
    )

    # The person an agent wrote it for, named in the agent's card on the page.
    has_one(:person, Regents.Patchbay.Members.Member,
      source_attribute: :beneficiary_profile_id,
      destination_attribute: :id,
      public?: true
    )

    # Oldest first, so readers see who liked it in the order they did.
    has_many :likes, Regents.Patchbay.Forum.Like do
      sort(inserted_at: :asc)
    end

    has_many(:answer_uses, Regents.Patchbay.Forum.AnswerUse)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
