defmodule RegentsWeb.Patchbay.PostListLive do
  @moduledoc """
  The first page of the home page's Recent list of every post, kept current
  while it is open.

  A post that starts published arrives at the top, and the list keeps its
  page's length, so the last row leaves as it does. A shown post's replies,
  likes and solved mark change in place, and a post moderation hides leaves.
  Every change comes as a notice on the site's PubSub that carries the row
  (`Regents.Patchbay.Forum.LivePost`), so the list reads nothing when one
  arrives. Nothing tells those topics yet: the writes come with Patchbay's
  writing pages.

  Drawn with the page, the list takes the posts the page already read; it
  reads its first page itself once when it joins.
  """
  use RegentsWeb, :live_view

  import RegentsWeb.Patchbay.Forum.BoardHTML, only: [post_row: 1, posts_empty: 1]

  alias Regents.Patchbay.Forum.LivePost
  alias RegentsWeb.Patchbay.Forum.Discussions

  @impl true
  def mount(_params, session, socket) do
    # Listening starts before the list is read, so no post falls between.
    if connected?(socket),
      do: :ok = Phoenix.PubSub.subscribe(Regents.PubSub, LivePost.posts_topic())

    socket = assign_new(socket, :reports, &first_page/0)
    rows = Enum.map(socket.assigns.reports, &LivePost.row/1)
    ids = Enum.map(rows, & &1.id)
    if connected?(socket), do: Enum.each(ids, &follow/1)

    {:ok,
     socket
     |> assign(reports: nil, ids: ids, empty: rows == [], empty_words: session["empty"])
     |> stream_configure(:posts, dom_id: &"feed-#{&1.id}")
     |> stream(:posts, rows, limit: Discussions.page_size()), layout: false}
  end

  @impl true
  def handle_info(%{event: "posted", payload: row}, socket) do
    %{ids: ids} = socket.assigns

    if row.id in ids do
      {:noreply, socket}
    else
      follow(row.id)
      {kept, dropped} = Enum.split([row.id | ids], Discussions.page_size())
      Enum.each(dropped, &unfollow/1)

      {:noreply,
       socket
       |> assign(ids: kept, empty: false)
       |> stream_insert(:posts, row, at: 0, limit: Discussions.page_size())}
    end
  end

  def handle_info(%{event: "changed", payload: %{thread: row}}, socket) do
    cond do
      row.id not in socket.assigns.ids ->
        {:noreply, socket}

      LivePost.published?(row) ->
        {:noreply, stream_insert(socket, :posts, row, update_only: true)}

      true ->
        unfollow(row.id)

        {:noreply,
         socket
         |> assign(ids: List.delete(socket.assigns.ids, row.id))
         |> stream_delete(:posts, row)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ol
      id="pb-home-posts-rows"
      class="pb-feed-list"
      phx-update="stream"
      phx-hook="MotionArrivals"
      data-glow
    >
      <.post_row :for={{id, post} <- @streams.posts} id={id} post={post} live />
    </ol>
    <.posts_empty :if={@empty} empty={@empty_words} offer_ask={false} />
    """
  end

  # Joined, the list reads its first page once; drawn with the page, it has
  # the page's own posts.
  defp first_page do
    {:ok, filters} = Discussions.filters(%{})
    {:ok, posts, _next} = Discussions.page(filters, nil)
    posts
  end

  defp follow(id),
    do: :ok = Phoenix.PubSub.subscribe(Regents.PubSub, LivePost.post_topic(id))

  defp unfollow(id),
    do: :ok = Phoenix.PubSub.unsubscribe(Regents.PubSub, LivePost.post_topic(id))
end
