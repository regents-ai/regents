defmodule RegentsWeb.Patchbay.ThreadLive do
  @moduledoc """
  A post's thread on its page, kept current while it is open: a new reply
  arrives at the end of the last page of replies, and likes, the asker's
  pick, "it worked" counts and the reply count change in place. Replies are
  never reordered under the reader. A reply moderation hides leaves, and a
  thread moderation hides sends the reader to its address, which no longer
  shows it.

  Every change comes as a notice on the site's PubSub that carries what the
  page draws (`Regents.Patchbay.Forum.LivePost`), so the thread reads nothing
  when one arrives. Nothing tells that topic yet: the writes come with
  Patchbay's writing pages.

  Drawn with the page, the thread takes what the page has just read
  (`assign_new/3` finds it in the page's assigns); a live connection reads it
  again, once. The evidence and the payment are drawn with the page only and
  kept as drawn. When that read fails, the thread says so in the words of the
  page that answers 503, with its Retry link, and stays as it is: notices are
  ignored and nothing is read again until the reader asks.
  """
  use RegentsWeb, :live_view

  require Logger

  import RegentsWeb.Patchbay.Forum.BoardHTML, only: [replies_unavailable: 1, thread_body: 1]

  alias Regents.Patchbay.Forum.LivePost
  alias RegentsWeb.Patchbay.Forum.Board

  # What a notice changes on the post itself.
  @live [
    :reply_count,
    :solved,
    :post_like_count,
    :thread_like_count,
    :view_count,
    :last_activity_at,
    :solution_reply_id,
    :accepted_reply_id,
    :solution_reply,
    :post_likes
  ]

  @impl true
  def mount(_params, %{"report_id" => id, "path" => path} = session, socket) do
    if connected?(socket),
      do: :ok = Phoenix.PubSub.subscribe(Regents.PubSub, LivePost.post_topic(id))

    socket =
      socket
      |> assign(path: path)
      |> assign_new(:report, fn -> read_report(id) end)

    case socket.assigns.report do
      nil -> {:ok, redirect(socket, to: path)}
      :unavailable -> {:ok, unavailable(socket, session), layout: false}
      report -> {:ok, open(socket, report, session), layout: false}
    end
  end

  @impl true
  def handle_info(_notice, %{assigns: %{retry: _retry}} = socket), do: {:noreply, socket}

  def handle_info(%{event: "changed", payload: %{thread: thread, reply: reply}}, socket) do
    if LivePost.published?(thread),
      do: {:noreply, socket |> put_thread(thread) |> put_reply(reply)},
      else: {:noreply, redirect(socket, to: socket.assigns.path)}
  end

  # The thread takes no presses here; one sent by hand changes nothing.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(%{retry: _retry} = assigns) do
    ~H"""
    <.replies_unavailable retry={@retry} path={@path} />
    """
  end

  def render(assigns), do: thread_body(assigns)

  defp read_report(id) do
    case Board.fetch_report(id) do
      {:ok, report} -> report
      :error -> nil
      {:error, failure} -> failed(failure)
    end
  end

  defp open(socket, report, session) do
    socket = assign_new(socket, :thread, fn -> read_thread(report, session) end)

    case socket.assigns.thread do
      :unavailable ->
        unavailable(socket, session)

      thread ->
        socket
        |> assign(thread)
        |> assign(thread: nil, reply_report: report)
    end
  end

  defp read_thread(report, session) do
    case Board.thread_page(report, session["after"], session["replies"]) do
      {:ok, thread} -> thread
      {:error, failure} -> failed(failure)
    end
  end

  # A read that fails as the thread connects is logged by its kind only, as
  # the page's own is.
  defp failed(failure) do
    Logger.warning("Report replies unavailable: " <> inspect(Board.failure_kind(failure)))
    :unavailable
  end

  # Retry opens the same page of replies again, as the 503 page's does.
  defp unavailable(socket, %{"after" => cursor}) when is_binary(cursor),
    do: assign(socket, retry: socket.assigns.path <> "?" <> URI.encode_query(after: cursor))

  defp unavailable(socket, _session), do: assign(socket, retry: socket.assigns.path)

  defp put_thread(socket, thread) do
    %{report: report, reply_report: reply_report} = socket.assigns

    assign(socket,
      report: struct!(report, Map.take(thread, @live)),
      answer: thread.solution_reply,
      reply_report: %{
        reply_report
        | solution_reply_id: thread.solution_reply_id,
          accepted_reply_id: thread.accepted_reply_id
      }
    )
  end

  defp put_reply(socket, nil), do: socket

  defp put_reply(socket, reply) do
    replies = socket.assigns.replies
    index = Enum.find_index(replies, &(&1.id == reply.id))

    cond do
      index && LivePost.published?(reply) ->
        assign(socket, replies: List.replace_at(replies, index, reply))

      index ->
        assign(socket, replies: List.delete_at(replies, index))

      LivePost.published?(reply) and last_page?(socket.assigns) ->
        assign(socket, replies: replies ++ [reply])

      true ->
        socket
    end
  end

  # A new reply belongs at the end of every reply, on the page that ends the
  # thread while it has room.
  defp last_page?(%{reply_filter: filter, next_cursor: next, replies: replies}),
    do: filter == "all" and is_nil(next) and length(replies) < Board.replies_per_page()
end
