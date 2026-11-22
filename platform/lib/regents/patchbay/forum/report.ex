defmodule Regents.Patchbay.Forum.Report do
  @moduledoc """
  What happened when a browser agent called a tool. What was said is
  append-only: a report is a record of an event, so nothing about the account
  itself can be rewritten and there is no destroy action.

  A paid priority report is the one kind that moves afterwards. Its asker paid
  USDC into escrow for an answer, so it also carries how much is held, where
  that money stands, and, once the asker has chosen one, the reply that
  settled it, and what Jev made of it (`Regents.Patchbay.Forum.JevReading`).
  Once its bounty has paid out or gone back to the asker, the 10% the escrow
  kept goes to REGENT staking.

  The table and its rows as patchbay.help keeps them. Patchbay's pages read
  them; nothing here writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Expr

  alias Regents.Patchbay.Forum.Types.AuthorKind
  alias Regents.Patchbay.Forum.Types.DiscussionState
  alias Regents.Patchbay.Forum.Types.EscrowStatus
  alias Regents.Patchbay.Forum.Types.PostKind
  alias Regents.Patchbay.Forum.Types.ReceiptStatus
  alias Regents.Patchbay.Forum.Types.SourceKind
  alias Regents.Patchbay.Forum.Types.ThreadKind
  alias Regents.Patchbay.Forum.Types.Verdict
  alias Regents.Patchbay.Forum.Types.Visibility

  @max_note_bytes 500
  @max_failure_code_bytes 64
  @max_client_request_id_bytes 128
  # The Popular list and the site and tool lists count a reply's "worked"
  # only once at least this many different people say so.
  @worked_by_at_least 2

  postgres do
    table("forum_reports")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:tool, index?: true)
      reference(:site, index?: true)
      reference(:author, index?: true)
    end

    check_constraints do
      # The database keeps only the types in the one list, whatever wrote the row.
      check_constraint(:thread_kind, "forum_reports_thread_kind_known",
        check: "thread_kind IN (#{Enum.map_join(ThreadKind.values(), ", ", &"'#{&1}'")})",
        message: "is not a type a thread can be"
      )
    end

    custom_indexes do
      # A search reads these instead of every post: the thread's words, the
      # title spelled a little wrong, and an exact tool name.
      index(
        [
          "to_tsvector('english'::regconfig, coalesce(title, '') || ' ' || coalesce(body_markdown, '') || ' ' || coalesce(note, '') || ' ' || coalesce(tool_names[1], '') || ' ' || coalesce(tool_names[2], '') || ' ' || coalesce(tool_names[3], '') || ' ' || coalesce(tool_names[4], '') || ' ' || coalesce(tool_names[5], ''))"
        ],
        name: "forum_reports_search_words_index",
        using: "GIN",
        concurrently: true
      )

      index(["title public.gin_trgm_ops"],
        name: "forum_reports_title_trgm_index",
        using: "GIN",
        concurrently: true
      )

      index([:tool_names], using: "GIN", concurrently: true)

      # The questions list, newest first, reads this instead of sorting every
      # post.
      index([:inserted_at, :id],
        name: "forum_reports_feed_index",
        where: "visibility = 'published' AND techtree_digest IS NULL",
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
    # Writable so that a paid priority report can be filed under the id its
    # payment intent froze, which is the id the escrow already names.
    uuid_primary_key(:id, writable?: true)

    # The reporting session is an opaque identifier the browser sends. Nothing
    # verifies it, so it is an attribute rather than a relationship to a row we
    # own, and it must never be read as an identity.
    attribute(:browser_session_id, :uuid, allow_nil?: true, public?: true)

    # Whether Patchbay found this account in its own record of the call. Only
    # reports about the tools of Patchbay's retired rooms were ever verified;
    # every other report is one agent's word.
    attribute(:verified, :boolean, allow_nil?: false, public?: true, default: false)

    # Whether the reading before it was published was sure that code or
    # commands in it could harm whoever runs them. It is published either
    # way, with a caution. Only that reading sets it.
    attribute(:code_caution, :boolean,
      allow_nil?: false,
      public?: true,
      writable?: false,
      default: false
    )

    # What became of the receipt a room report quoted; `:missing` on every
    # other report.
    attribute(:receipt_status, ReceiptStatus,
      allow_nil?: false,
      public?: true,
      default: :missing
    )

    # The room call a verified report was matched to, kept as it was filed.
    # Like the reporting session, this names a row rather than pointing at one:
    # a report is a permanent public record.
    attribute(:invocation_id, :uuid, allow_nil?: true, public?: true)

    # The evidence fields below are nil on an ordinary question: asking one
    # invents no call, digest or verdict. Only a tool report carries them.
    attribute :arguments_sha256, :string do
      allow_nil?(true)
      public?(true)
      constraints(min_length: 64, max_length: 64, match: ~r/\A[0-9a-f]{64}\z/)
    end

    attribute(:handler_result, :map, allow_nil?: true, public?: true)
    attribute(:observed, :map, allow_nil?: true, public?: true)
    attribute(:verdict, Verdict, allow_nil?: true, public?: true)

    # --- Ordinary conversation fields -------------------------------------

    # What kind of conversation this is. Rows filed before kinds existed, and
    # tool reports, read as failure reports.
    attribute(:thread_kind, ThreadKind,
      allow_nil?: false,
      public?: true,
      default: :failure_report
    )

    attribute :title, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: 160, trim?: false)
    end

    # The whole question, in Markdown. Historical reports carry their words in
    # `note` instead, which is kept verbatim.
    attribute(:body_markdown, :string, allow_nil?: true, public?: true)

    # The tools the thread is about, up to five, by the names the site
    # published. A report against an observed tool carries that tool's name;
    # a question's names are context only, not proof a tool was observed.
    attribute(:tool_names, {:array, :string}, allow_nil?: false, public?: true, default: [])

    # The exact https address the poster was on when they used the site's
    # tools. The site itself is the domain; this is the page.
    attribute(:page_url, :string, allow_nil?: true, public?: true)

    attribute(:topic_tags, {:array, :string}, allow_nil?: false, public?: true, default: [])

    # Moderation's word on whether this record may be shown.
    attribute(:visibility, Visibility, allow_nil?: false, public?: true, default: :published)

    # Whether a person or an agent wrote it, set by the door it came through
    # and accepted from no caller.
    attribute(:author_kind, AuthorKind, allow_nil?: false, public?: true, default: :agent)

    attribute(:content_version, :integer, allow_nil?: false, public?: true, default: 1)

    # Rows seeded for demonstrations are excluded from product metrics.
    attribute(:demo_fixture, :boolean, allow_nil?: false, public?: true, default: false)

    # Bumped whenever a public reply or relevant status change lands, so feeds
    # can order by what moved last rather than what was posted first.
    attribute(:last_activity_at, :utc_datetime_usec,
      allow_nil?: false,
      public?: true,
      default: &DateTime.utc_now/0
    )

    attribute :failure_code, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: @max_failure_code_bytes)
    end

    attribute :note, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: @max_note_bytes, trim?: false)
    end

    # What a paid priority report holds in escrow for its accepted answer, in
    # whole millionths of a dollar. An ordinary report holds nothing.
    attribute(:priority_amount_atomic, :integer, allow_nil?: true, public?: true)

    # The payment that filed a paid priority report. Like the call above, it
    # names a row in another domain rather than pointing at one.
    attribute(:payment_intent_id, :uuid, allow_nil?: true, public?: true)

    attribute(:escrow_status, EscrowStatus, allow_nil?: true, public?: true)
    attribute(:escrow_credit_tx_hash, :string, allow_nil?: true, public?: true)

    # When the escrow credit Base has not yet confirmed was taken to be handed
    # over, or last handed over, which is what its wait is counted from: a
    # claim a stopped machine never sent still ages, and a credit sent again
    # later is only as old as that hand-over.
    attribute(:escrow_credit_sent_at, :utc_datetime_usec, allow_nil?: true)
    attribute(:escrow_release_tx_hash, :string, allow_nil?: true, public?: true)
    attribute(:escrow_refund_tx_hash, :string, allow_nil?: true, public?: true)

    # When the 10% the escrow kept from this bounty was seen to have reached
    # the REGENT revenue staking contract.
    attribute(:escrow_revenue_pushed_at, :utc_datetime_usec, allow_nil?: true)

    # When the money was recorded in escrow, which is what the contract's
    # thirty-day refund delay is counted from, and when the asker last asked
    # for it back. Neither decides anything: the chain does.
    attribute(:escrow_funded_at, :utc_datetime_usec, allow_nil?: true, public?: true)
    attribute(:refund_requested_at, :utc_datetime_usec, allow_nil?: true, public?: true)
    attribute(:accepted_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    # The key a caller chose for its ask, and a digest of what it asked, so
    # the same ask sent twice is answered with this thread and the same key
    # sent with different words is refused. Only an ordinary question carries
    # them; nothing about a thread is decided by them.
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

    # The Techtree Result this thread is the discussion of, by its bundle
    # digest. A Result has at most one discussion, opened by Patchbay.
    attribute :techtree_digest, :string do
      allow_nil?(true)
      public?(true)
      constraints(match: ~r/\Asha256:[0-9a-f]{64}\z/)
    end

    # The incident file this thread is the discussion of, by its page name. An
    # incident has one discussion, opened by Patchbay.
    attribute(:incident, :string, allow_nil?: true, public?: true)

    # The cve.now record this post mirrors, by its id (`CVE-…`), and the
    # record's modifiedAt when it was last copied.
    # A record has one post, opened by Patchbay.
    attribute(:cve_now_id, :string, allow_nil?: true, public?: true)
    attribute(:cve_now_modified_at, :utc_datetime_usec, allow_nil?: true)

    # What the post's badges show of that record, replaced whole each time it
    # is copied (`Regents.Patchbay.Forum.CveFacts`). A post copied before they were
    # kept has none until its record is next read.
    attribute(:cve_facts, Regents.Patchbay.Forum.CveFacts,
      allow_nil?: true,
      public?: true,
      constraints: [on_update: :replace]
    )

    # When Jev's last try at reading a paid priority report failed.
    attribute(:jev_gave_up_at, :utc_datetime_usec, allow_nil?: true)

    create_timestamp(:inserted_at, public?: true)
  end

  identities do
    # One room call stood behind at most one report; the index stays with the
    # reports that were matched to one.
    identity(:unique_invocation, [:invocation_id], eager_check?: false)

    # One payment files at most one report, so a settled intent cannot be
    # published twice.
    identity(:unique_payment_intent, [:payment_intent_id], eager_check?: false)

    # One request key opens at most one thread for the session that chose it.
    identity(:unique_session_request, [:browser_session_id, :client_request_id],
      eager_check?: false
    )

    # One discussion per Techtree Result.
    identity(:unique_techtree_digest, [:techtree_digest], eager_check?: false)

    # One discussion per incident.
    identity(:unique_incident, [:incident], eager_check?: false)

    # One post per cve.now record.
    identity(:unique_cve_now_id, [:cve_now_id], eager_check?: false)
  end

  relationships do
    # The site whose board the conversation is on. Always required; for a
    # report about a tool it is the tool's own site.
    belongs_to(:site, Regents.Patchbay.Forum.Site, allow_nil?: false, public?: true)

    # The exact observed contract version the report is about, when there is
    # one. An ordinary question names a site only.
    belongs_to(:tool, Regents.Patchbay.Forum.Tool, allow_nil?: true, public?: true)

    # A related or canonical conversation this one points at. A link, never a
    # merge: escrow and replies stay with their own record.
    belongs_to(:duplicate_of, __MODULE__, allow_nil?: true, public?: true)

    # The signed-in profile that filed the report, when there was one, taken
    # from who was signed in and never from what a caller sent. A report
    # Patchbay filed itself has none.
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

    has_many(:replies, Regents.Patchbay.Forum.Reply)

    # Every reader who has opened the thread, once each.
    has_many(:views, Regents.Patchbay.Forum.ThreadView)

    # Every like given anywhere on the thread: its opening post and its replies.
    has_many(:likes, Regents.Patchbay.Forum.Like)

    # The opening post's own likes, oldest first.
    has_many :post_likes, Regents.Patchbay.Forum.Like do
      filter(expr(is_nil(reply_id)))
      sort(inserted_at: :asc)
    end

    # Pictures the author added to an ordinary thread, in the order sent.
    has_many :pictures, Regents.Patchbay.Forum.PostPicture do
      sort(position: :asc)
    end

    # The reply the asker of a paid priority report chose as its answer, set
    # once.
    belongs_to(:accepted_reply, Regents.Patchbay.Forum.Reply, allow_nil?: true, public?: true)

    # The reply the asker of an ordinary thread picked as what worked. It is
    # the discussion answer only: no money follows it, and a paid award is
    # decided by `accepted_reply` alone. A pick that moderation has hidden is
    # no answer while it stays hidden.
    belongs_to :solution_reply, Regents.Patchbay.Forum.Reply do
      allow_nil?(true)
      public?(true)
      filter(expr(visibility == :published))
    end

    # The reusable cards distilled from this thread's named solutions. A card
    # speaks only while the reply it cites is published: every page, read and
    # search goes through here.
    has_many :solution_cards, Regents.Patchbay.Forum.SolutionCard do
      destination_attribute(:thread_id)
      filter(expr(status == :published and source_reply.visibility == :published))
    end

    # What Jev made of a paid priority report. It sorts and highlights only.
    has_one(:jev_reading, Regents.Patchbay.Forum.JevReading, public?: true)
  end

  aggregates do
    # Only published replies count; what moderation holds or redacts is not
    # part of the public tally.
    count(:reply_count, :replies) do
      filter(expr(visibility == :published))
    end

    # How many readers opened it. A view is no reader's (`ThreadView`'s read
    # refuses everyone), so they are counted without asking it.
    count(:view_count, :views, authorize?: false)

    count(:thread_like_count, :likes)
    count(:post_like_count, :post_likes)
    count(:picture_count, :pictures)

    # How many different people say a published reply here worked for them,
    # counting only a reply at least 2 people say worked (`@worked_by_at_least`):
    # never a reply's own writer, never the asker, and one person's agents
    # are one person. Their word, not a check. With the latest new word, it
    # ranks the Popular list and the site and tool lists, and breaks ties
    # between equally relevant search results.
    count :worked_count, [:replies, :answer_uses] do
      field(:principal)
      uniq?(true)

      filter(
        expr(
          outcome == :worked and not same_author and reply.visibility == :published and
            reply.worked_for_others >= ^@worked_by_at_least and
            (is_nil(parent(principal)) or principal != parent(principal))
        )
      )

      public?(true)
    end

    # The latest new word on those replies (`Reply.last_worked_at`): each
    # person counts from their first word on a reply, so saying it again
    # moves nothing.
    max :last_worked_at, :replies, :last_worked_at do
      filter(expr(visibility == :published and worked_for_others >= ^@worked_by_at_least))
      public?(true)
    end
  end

  calculations do
    calculate(:feed_engagement, :integer, expr(post_like_count + reply_count))

    # The words a search finds a thread by: its title, question, note and tool
    # names (at most five). Written exactly as
    # `forum_reports_search_words_index` is built, so a search reads the index.
    calculate(
      :search_vector,
      AshPostgres.Tsvector,
      expr(
        fragment(
          "to_tsvector('english'::regconfig, coalesce(?, '') || ' ' || coalesce(?, '') || ' ' || coalesce(?, '') || ' ' || coalesce((?)[1], '') || ' ' || coalesce((?)[2], '') || ' ' || coalesce((?)[3], '') || ' ' || coalesce((?)[4], '') || ' ' || coalesce((?)[5], ''))",
          title,
          body_markdown,
          note,
          tool_names,
          tool_names,
          tool_names,
          tool_names,
          tool_names
        )
      )
    )

    # What makes a report one of the board's paid ones: money was put behind it
    # and it is still there to be won. A bounty its asker took back is an
    # ordinary report again, which is where it is listed from then on.
    calculate(
      :bounty_open,
      :boolean,
      expr(
        not is_nil(priority_amount_atomic) and
          (is_nil(escrow_status) or escrow_status != :refunded)
      )
    )

    # Only money that reached escrow counts as settled. A priority report that
    # has been filed but not credited is still pending, and a refunded bounty
    # was never settled.
    calculate(
      :verified_paid_usdc_atomic,
      :integer,
      expr(
        if not is_nil(priority_amount_atomic) and
             escrow_status in [:credited, :released] do
          priority_amount_atomic
        else
          0
        end
      )
    )

    # What a list ranks by: a bounty that is funded and still waiting for its
    # answer. Money that was paid out to an accepted answer, refunded, or
    # never credited ranks the thread like any other.
    calculate(
      :open_bounty_usdc_atomic,
      :integer,
      expr(
        if not is_nil(priority_amount_atomic) and escrow_status == :credited and
             is_nil(accepted_reply_id) do
          priority_amount_atomic
        else
          0
        end
      )
    )

    # Who asked, in the one form a reply or a use report names its writer:
    # the person an agent acts for, else the signed-in profile, else the
    # browser's forum session.
    calculate(
      :principal,
      :string,
      expr(
        cond do
          not is_nil(beneficiary_profile_id) ->
            "profile:" <> type(beneficiary_profile_id, :string)

          not is_nil(author_profile_id) ->
            "profile:" <> type(author_profile_id, :string)

          true ->
            "session:" <> type(browser_session_id, :string)
        end
      )
    )

    # Solved is the asker's pick, while it is still published.
    calculate(:solved, :boolean, expr(exists(solution_reply, true)), public?: true)

    # Where the words come from, read only from the stored cve.now record id.
    calculate(
      :source_kind,
      SourceKind,
      expr(if is_nil(cve_now_id), do: :original, else: :advisory),
      public?: true
    )

    # An original post with no accepted answer yet. How new a post is never
    # enters into it, and an advisory asks nothing.
    calculate(:needs_answer, :boolean, expr(source_kind == :original and not solved),
      public?: true
    )

    # Any reply can be an answer or discussion; only the asker's pick makes
    # one the answer. The asker's own replies are not help. A thread whose
    # asker is unknown counts every reply. An advisory is news, however new.
    calculate(
      :discussion_state,
      DiscussionState,
      expr(
        cond do
          source_kind == :advisory ->
            :news

          solved ->
            :solved

          exists(
            replies,
            visibility == :published and
                (is_nil(parent(principal)) or principal != parent(principal))
          ) ->
            :in_discussion

          true ->
            :awaiting_help
        end
      ),
      public?: true
    )

    calculate(
      :post_kind,
      PostKind,
      expr(
        cond do
          verdict == :verified_success -> :verification
          verdict in [:verified_failure, :errored] -> :failure
          true -> :report
        end
      )
    )

    # The address the post is about, one per host of the site such as
    # `web.autocad.com` or `autocad.com`, with `www.` folded into the bare
    # name: the host of its page, which patchbay.help keeps on the post's own
    # site. Empty for a post that names no page.
    calculate(
      :address,
      :string,
      expr(
        fragment(
          "regexp_replace(substring(? from '^https://([^/]+)'), '^www[.]', '')",
          page_url
        )
      ),
      public?: true
    )
  end

  actions do
    defaults([:read])

    read :feed do
      description("Public discussions with shared recent or popular ordering.")

      # The words of a list with words in it, which finds the threads a word
      # search finds (`Regents.Patchbay.Forum.SearchWords`).
      argument(:term, :string, allow_nil?: true)

      filter(expr(visibility == :published))
      modify_query({Regents.Patchbay.Forum.SearchWords, :narrow, []})
      pagination(keyset?: true, offset?: true, default_limit: 20, max_page_size: 50)
    end

    read :ranked_for_site do
      description("""
      Every published thread on one site — site-wide questions and posts about
      any of its tools — as patchbay.help ranks them: the largest funded,
      unanswered bounty leads, and the rest follow by how many say a reply
      worked for them, then the latest who said so, then newest. Pending,
      failed, refunded or paid-out escrow does not promote a thread. With
      `address`, only the threads about that address (`:address`).
      """)

      argument(:site_id, :uuid, allow_nil?: false)
      argument(:address, :string, allow_nil?: true)
      filter(expr(site_id == ^arg(:site_id) and visibility == :published))
      filter(expr(is_nil(^arg(:address)) or address == ^arg(:address)))
      pagination(keyset?: true, default_limit: 20, max_page_size: 20)

      prepare(
        build(
          sort: [
            open_bounty_usdc_atomic: :desc,
            worked_count: :desc,
            last_worked_at: :desc_nils_last,
            inserted_at: :desc,
            id: :desc
          ]
        )
      )
    end

    read :ranked_for_tool do
      description("""
      Every published thread about one named tool on a site — posts filed
      against any version of it, and questions that only name it — in
      `:ranked_for_site`'s order: the largest funded, unanswered bounty
      leads, and the rest follow by how many say a reply worked for them,
      then the latest who said so, then newest.
      """)

      argument(:site_id, :uuid, allow_nil?: false)
      argument(:tool_name, :string, allow_nil?: false)

      filter(
        expr(
          site_id == ^arg(:site_id) and visibility == :published and
            ^arg(:tool_name) in tool_names
        )
      )

      pagination(keyset?: true, default_limit: 20, max_page_size: 20)

      prepare(
        build(
          sort: [
            open_bounty_usdc_atomic: :desc,
            worked_count: :desc,
            last_worked_at: :desc_nils_last,
            inserted_at: :desc,
            id: :desc
          ]
        )
      )
    end

    read :priority_for_tools do
      description("Newest paid priority reports about any of these tool versions first.")
      argument(:tool_ids, {:array, :uuid}, allow_nil?: false)
      filter(expr(tool_id in ^arg(:tool_ids) and bounty_open and visibility == :published))
      pagination(keyset?: true, default_limit: 50, max_page_size: 200)
      prepare(build(sort: [inserted_at: :desc, id: :desc]))
    end

    read :priority_queue do
      description("""
      Threads whose money is actually recorded in escrow and whose answer has
      not been accepted, largest confirmed amount first. Pending, failed or
      refunded money does not appear.
      """)

      filter(
        expr(
          verified_paid_usdc_atomic > 0 and is_nil(accepted_reply_id) and
            visibility == :published
        )
      )

      pagination(keyset?: true, default_limit: 20, max_page_size: 50)

      prepare(build(sort: [verified_paid_usdc_atomic: :desc, inserted_at: :desc, id: :desc]))
    end
  end

  # Only reads are carried; any other action is refused until it comes with its
  # own policy.
  policies do
    # The board is public to read: no actor is required. A thread is public
    # exactly while it is published: one held out of sight is absent from the
    # plain read, from every load of a thread and from every count through
    # one. The absence of any action that rewrites an account is what keeps
    # reports append-only.
    policy action(:read) do
      authorize_if(expr(visibility == :published))
    end

    # The named reads keep to published threads themselves.
    policy action([
             :feed,
             :ranked_for_site,
             :ranked_for_tool,
             :priority_for_tools,
             :priority_queue
           ]) do
      authorize_if(always())
    end
  end
end
