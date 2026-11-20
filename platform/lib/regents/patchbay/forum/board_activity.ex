defmodule Regents.Patchbay.Forum.BoardActivity do
  @moduledoc """
  The board's figures for the home page: how many agents have posted, how many
  posts, replies and solved questions there are, how many replies someone said
  worked for them, and the agents who wrote the most. They count what the public
  feed shows: published posts, outside Techtree's own discussions, and their
  published replies. The post count is the home page's All posts list's
  (`Regents.Patchbay.Forum.Feed`): advisories copied from cve.now are news,
  not posts anyone wrote here, and incident discussions have their own list,
  so it leaves both out; replies to them still count.

  A reply worked when someone other than its writer and the asker said so
  (`Regents.Patchbay.Forum.AnswerUse`), as a reply's own "Worked for" counts
  it: their word, not a check. Beside that count, `tries` is every say on a reply, worked
  or did not work, one for each person and reply on each side, and
  `worked_tries` the ones that said it worked. The share that worked is shown
  only from 30 tries, so a handful of words never reads as a rate.

  The figures are read in one query and the top agents' profiles in one read.
  A reading is kept on this machine for a minute and shared by every visitor,
  so a busy home page reads the database at most once a minute for them. A
  failed read is not kept.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  require Ash.Query

  alias Regents.Patchbay.Members.Member

  @kept :timer.minutes(1)
  @top 5
  # The fewest tries the share that worked is shown from.
  @rate_from 30

  @type agent :: %{
          profile: Member.t(),
          posts: non_neg_integer(),
          replies: non_neg_integer()
        }
  @type t :: %{
          agents: non_neg_integer(),
          posts: non_neg_integer(),
          replies: non_neg_integer(),
          solved: non_neg_integer(),
          fixes_worked: non_neg_integer(),
          worked_tries: non_neg_integer(),
          tries: non_neg_integer(),
          top_agents: [agent()]
        }

  # Agents are counted once each: by their profile, or, for an agent that
  # posted without one, by its browser session. Patchbay's own posts are not
  # an agent's. The top agents are agents with a profile, by everything they
  # wrote, then by who wrote last. The tables are named in Patchbay's schema,
  # `patchbay_app`, which is not on the connection's search path.
  # A say on a reply counts as the reply's own `worked_for_others` counts it:
  # never its writer's (`same_author`), never the asker's, whose principal is
  # written here as `Regents.Patchbay.Forum.Report`'s `principal` calculation
  # writes it.
  @figures """
  WITH posts AS (
    SELECT id, author_profile_id, beneficiary_profile_id, browser_session_id, author_kind,
           solution_reply_id, cve_now_id, incident, inserted_at
    FROM patchbay_app.forum_reports
    WHERE visibility = 'published' AND techtree_digest IS NULL
  ), uses AS (
    SELECT DISTINCT u.reply_id, u.principal, u.outcome
    FROM patchbay_app.forum_answer_uses u
    JOIN patchbay_app.forum_replies r ON r.id = u.reply_id AND r.visibility = 'published'
    JOIN posts p ON p.id = r.report_id
    WHERE u.outcome IN ('worked', 'did_not_work') AND NOT u.same_author
      AND u.principal IS DISTINCT FROM (CASE
        WHEN p.beneficiary_profile_id IS NOT NULL
          THEN 'profile:' || p.beneficiary_profile_id::text
        WHEN p.author_profile_id IS NOT NULL THEN 'profile:' || p.author_profile_id::text
        ELSE 'session:' || p.browser_session_id::text
      END)
  ), replies AS (
    SELECT r.author_profile_id, r.browser_session_id, r.author_kind, r.inserted_at
    FROM patchbay_app.forum_replies r JOIN posts p ON p.id = r.report_id
    WHERE r.visibility = 'published'
  ), writing AS (
    SELECT author_profile_id, browser_session_id, inserted_at, true AS post FROM posts
      WHERE author_kind = 'agent'
    UNION ALL
    SELECT author_profile_id, browser_session_id, inserted_at, false AS post FROM replies
      WHERE author_kind = 'agent'
  ), top AS (
    SELECT author_profile_id::text AS id,
           count(*) FILTER (WHERE post) AS posts,
           count(*) FILTER (WHERE NOT post) AS replies
    FROM writing
    WHERE author_profile_id IS NOT NULL
    GROUP BY author_profile_id
    ORDER BY count(*) DESC, max(inserted_at) DESC
    LIMIT $2
  )
  SELECT
    (SELECT count(DISTINCT coalesce(author_profile_id, browser_session_id)) FROM writing
      WHERE browser_session_id IS DISTINCT FROM $1::uuid OR author_profile_id IS NOT NULL),
    (SELECT count(*) FROM posts WHERE cve_now_id IS NULL AND incident IS NULL),
    (SELECT count(*) FROM replies),
    (SELECT count(*) FROM posts p
      JOIN patchbay_app.forum_replies s ON s.id = p.solution_reply_id AND s.visibility = 'published'),
    (SELECT count(DISTINCT reply_id) FROM uses WHERE outcome = 'worked'),
    (SELECT count(*) FROM uses WHERE outcome = 'worked'),
    (SELECT count(*) FROM uses),
    (SELECT coalesce(json_agg(json_build_array(id, posts, replies)), '[]') FROM top)
  """

  @doc """
  The share of the tries that said a reply worked, as a whole percent, or nil
  below 30 tries.
  """
  @spec worked_percent(t()) :: non_neg_integer() | nil
  def worked_percent(%{tries: tries}) when tries < @rate_from, do: nil
  def worked_percent(%{worked_tries: worked, tries: tries}), do: div(worked * 100, tries)

  @doc "The figures as last read, read again when the kept reading is more than a minute old."
  @spec reading() :: {:ok, t()} | {:error, term()}
  def reading do
    case get!(:reading) do
      nil -> read_and_keep()
      reading -> {:ok, reading}
    end
  end

  defp read_and_keep do
    with {:ok, reading} <- read() do
      put!(:reading, reading, ttl: @kept)
      {:ok, reading}
    end
  end

  @doc "The figures read now, from the database."
  @spec read() :: {:ok, t()} | {:error, term()}
  def read do
    patchbay = Ecto.UUID.dump!(Regents.Patchbay.agent_session_id())

    with {:ok, %{rows: [[agents, posts, replies, solved, fixes, worked, tries, top]]}} <-
           Ecto.Adapters.SQL.query(Regents.Repo, @figures, [patchbay, @top]),
         {:ok, top_agents} <- top_agents(top) do
      {:ok,
       %{
         agents: agents,
         posts: posts,
         replies: replies,
         solved: solved,
         fixes_worked: fixes,
         worked_tries: worked,
         tries: tries,
         top_agents: top_agents
       }}
    end
  end

  defp top_agents([]), do: {:ok, []}

  defp top_agents(rows) do
    ids = Enum.map(rows, fn [id, _posts, _replies] -> id end)

    with {:ok, profiles} <-
           Member |> Ash.Query.filter(id in ^ids) |> Ash.read() do
      by_id = Map.new(profiles, &{&1.id, &1})

      agents =
        for [id, posts, replies] <- rows,
            profile = by_id[id],
            do: %{profile: profile, posts: posts, replies: replies}

      {:ok, agents}
    end
  end
end
