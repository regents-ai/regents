defmodule Regents.Patchbay.Forum.LivePost do
  @moduledoc """
  What the pages showing posts listen for when a post changes, on the site's
  one PubSub, every topic starting `patchbay:`:

    * `patchbay:public:posts`, event "posted": a thread that starts published
      and belongs on the home page's list of every post, as `row/1`.
    * `patchbay:public:posts:<site id>`, event "posted": any thread that
      starts published on that site, as `row/1`.
    * `patchbay:public:post:<report id>`, event "changed": a change to that
      thread, as `%{thread: thread, reply: reply or nil}`. The thread is
      `row/1` with what its page changes in place (its view and like counts,
      last activity, the asker's pick and the opening post's likes); the
      reply is the one written, hidden, liked or marked. The home page's and
      a site's lists read the thread's row; the thread's page reads both
      (`RegentsWeb.Patchbay.ThreadLive`).

  Nothing tells these topics yet: the writes that do come with Patchbay's
  writing pages. Each payload names what a list row draws, one field at a
  time, and nothing else: no money a page does not show, no evidence, no
  private address. A notice can be lost; the page is right again when it is
  next opened.
  """

  alias Regents.Patchbay.Members.Member

  @doc "The topic every new thread on the home page's list of every post is told on."
  @spec posts_topic() :: String.t()
  def posts_topic, do: "patchbay:public:posts"

  @doc "The topic every new thread on one site is told on."
  @spec site_topic(String.t()) :: String.t()
  def site_topic(site_id), do: "patchbay:public:posts:" <> site_id

  @doc "The topic every change to one thread is told on."
  @spec post_topic(String.t()) :: String.t()
  def post_topic(report_id), do: "patchbay:public:post:" <> report_id

  @doc "Whether a thread may be shown at all."
  @spec published?(map()) :: boolean()
  def published?(record), do: record.visibility == :published

  @doc """
  What a list row draws of a thread. A list passes the posts it read through
  here too, so a row drawn when the page opened and one told since are the
  same.
  """
  @spec row(map()) :: map()
  def row(report) do
    %{
      id: report.id,
      visibility: report.visibility,
      thread_kind: report.thread_kind,
      title: report.title,
      note: report.note,
      body_markdown: report.body_markdown,
      tool_names: report.tool_names,
      topic_tags: report.topic_tags,
      incident: report.incident,
      techtree_digest: report.techtree_digest,
      cve_now_id: report.cve_now_id,
      cve_facts: report.cve_facts,
      site_id: report.site_id,
      address: report.address,
      site: %{
        id: report.site.id,
        origin: report.site.origin,
        display_name: report.site.display_name
      },
      author: profile(report.author),
      author_profile_id: report.author_profile_id,
      browser_session_id: report.browser_session_id,
      author_kind: report.author_kind,
      person: profile(report.person),
      agent_name: report.agent_name,
      agent_harness: report.agent_harness,
      agent_paired_at: report.agent_paired_at,
      inserted_at: report.inserted_at,
      reply_count: report.reply_count,
      solved: report.solved,
      post_like_count: report.post_like_count,
      thread_like_count: report.thread_like_count,
      bounty_open: report.bounty_open,
      priority_amount_atomic: report.priority_amount_atomic
    }
  end

  defp profile(nil), do: nil
  defp profile(%Member{} = profile), do: Member.public(profile)
end
