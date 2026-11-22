defmodule RegentsWeb.Patchbay.PostListLive do
  @moduledoc """
  The first page of a list of posts, kept current while it is open: the home
  page's Recent list of every post, and a site's posts. A site's posts about
  one address are a page like any later one, drawn without it.

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
  alias RegentsWeb.Patchbay.Forum.Board
  alias RegentsWeb.Patchbay.Forum.Discussions

  @impl true
  def mount(_params, session, socket) do
    list = list(session)
    # Listening starts before the list is read, so no post falls between.
    if connected?(socket), do: :ok = Phoenix.PubSub.subscribe(Regents.PubSub, list.topic)
    {socket, posts} = socket |> assign(list: list) |> first_page(list)
    rows = Enum.map(posts, &LivePost.row/1)
    ids = Enum.map(rows, & &1.id)
    if connected?(socket), do: Enum.each(ids, &follow/1)

    {:ok,
     socket
     |> assign(ids: ids, empty: rows == [])
     |> stream_configure(:posts, dom_id: &"feed-#{&1.id}")
     |> stream(:posts, rows, limit: list.size), layout: false}
  end

  @impl true
  def handle_info(%{event: "posted", payload: row}, socket) do
    %{list: list, ids: ids} = socket.assigns

    if row.id in ids do
      {:noreply, socket}
    else
      follow(row.id)
      {kept, dropped} = Enum.split([row.id | ids], list.size)
      Enum.each(dropped, &unfollow/1)

      {:noreply,
       socket
       |> assign(ids: kept, empty: false)
       |> stream_insert(:posts, row, at: 0, limit: list.size)}
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
      id={@list.id <> "-rows"}
      class="pb-feed-list"
      phx-update="stream"
      phx-hook="MotionArrivals"
      data-glow
    >
      <.post_row :for={{id, post} <- @streams.posts} id={id} post={post} likes={@list.likes} live />
    </ol>
    <.posts_empty :if={@empty} empty={@list.empty} offer_ask={false} />
    """
  end

  defp list(%{"list" => "home"} = session),
    do: %{
      id: "pb-home-posts",
      kind: :home,
      size: Discussions.page_size(),
      likes: :post,
      topic: LivePost.posts_topic(),
      empty: session["empty"]
    }

  defp list(%{"list" => "site", "site_id" => site_id, "origin" => origin} = session),
    do: %{
      id: "pb-site-posts",
      kind: :site,
      size: Board.ranked_page_size(),
      likes: :thread,
      topic: LivePost.site_topic(site_id),
      origin: origin,
      empty: session["empty"]
    }

  # Drawn with the page, the list has the page's own posts; joined, it reads
  # them once. Only the rows are kept, in the stream.
  defp first_page(socket, %{kind: :home}) do
    socket = assign_new(socket, :reports, &home_posts/0)
    {assign(socket, :reports, nil), socket.assigns.reports}
  end

  defp first_page(socket, %{kind: :site, origin: origin}) do
    socket = assign_new(socket, :posts, fn -> site_posts(origin) end)
    {assign(socket, :posts, nil), socket.assigns.posts}
  end

  defp home_posts do
    {:ok, filters} = Discussions.filters(%{})
    {:ok, posts, _next} = Discussions.page(filters, nil)
    posts
  end

  defp site_posts(origin) do
    {:ok, site} = Board.fetch_site(origin)
    {:ok, posts, _next} = Board.site_threads(site, nil, nil)
    posts
  end

  defp follow(id),
    do: :ok = Phoenix.PubSub.subscribe(Regents.PubSub, LivePost.post_topic(id))

  defp unfollow(id),
    do: :ok = Phoenix.PubSub.unsubscribe(Regents.PubSub, LivePost.post_topic(id))
end
