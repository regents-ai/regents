defmodule RegentsWeb.Patchbay.PostListLive do
  @moduledoc """
  The first page of a list of posts, kept current while it is open: the home
  page's Recent list of every post, a site's posts and a tool's posts. A
  site's posts about one address are a page like any later one, drawn
  without it.

  A post that starts published arrives at the top, and the list keeps its
  page's length, so the last row leaves as it does. A shown post's replies,
  likes and solved mark change in place, and a post moderation hides leaves.
  Every change comes as a notice on the site's PubSub that carries the row
  (`Regents.Patchbay.Forum.LivePost`), so the list reads nothing when one
  arrives. Nothing tells those topics yet: the writes come with Patchbay's
  writing pages.

  Drawn with the page, the list takes the posts the page already read; it
  reads its first page itself once when it joins. A read that fails as it
  joins says so in the list's place, with a link that opens the page again,
  and the list then hears nothing.
  """
  use RegentsWeb, :live_view

  require Logger

  import RegentsWeb.Patchbay.Forum.BoardHTML,
    only: [domain_path: 1, post_row: 1, posts_empty: 1, section_unavailable: 1, tool_path: 2]

  alias Regents.Patchbay.Forum.LivePost
  alias RegentsWeb.Patchbay.Forum.Board
  alias RegentsWeb.Patchbay.Forum.Discussions

  @impl true
  def mount(_params, session, socket) do
    list = list(session)
    # Listening starts before the list is read, so no post falls between.
    if connected?(socket), do: :ok = Phoenix.PubSub.subscribe(Regents.PubSub, list.topic)

    case socket |> assign(list: list) |> first_page(list) do
      {socket, :unavailable} -> {:ok, assign(socket, retry: list.path), layout: false}
      {socket, posts} -> {:ok, show(socket, posts), layout: false}
    end
  end

  defp show(socket, posts) do
    rows = Enum.map(posts, &LivePost.row/1)
    ids = Enum.map(rows, & &1.id)
    if connected?(socket), do: Enum.each(ids, &follow/1)

    socket
    |> assign(ids: ids, empty: rows == [])
    |> stream_configure(:posts, dom_id: &"feed-#{&1.id}")
    |> stream(:posts, rows, limit: socket.assigns.list.size)
  end

  @impl true
  def handle_info(_notice, %{assigns: %{retry: _retry}} = socket), do: {:noreply, socket}

  def handle_info(%{event: "posted", payload: row}, socket) do
    %{list: list, ids: ids} = socket.assigns

    if fits?(list, row) and row.id not in ids do
      follow(row.id)
      {kept, dropped} = Enum.split([row.id | ids], list.size)
      Enum.each(dropped, &unfollow/1)

      {:noreply,
       socket
       |> assign(ids: kept, empty: false)
       |> stream_insert(:posts, row, at: 0, limit: list.size)}
    else
      {:noreply, socket}
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

  # The list takes no presses; one sent by hand changes nothing.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(%{retry: _retry} = assigns) do
    ~H"""
    <.section_unavailable retry={@retry}>{@list.unavailable}</.section_unavailable>
    """
  end

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
    <.posts_empty :if={@empty} empty={@list.empty} ask={@list.ask} offer_ask={@list.ask != nil} />
    """
  end

  defp list(%{"list" => "home"} = session),
    do: %{
      id: "pb-home-posts",
      kind: :home,
      size: Discussions.page_size(),
      likes: :post,
      topic: LivePost.posts_topic(),
      empty: session["empty"],
      ask: nil,
      path: ~p"/patchbay",
      unavailable: "The questions could not be loaded just now."
    }

  defp list(%{"list" => "site", "site_id" => site_id, "origin" => origin} = session),
    do: %{
      id: "pb-site-posts",
      kind: :site,
      size: Board.ranked_page_size(),
      likes: :thread,
      topic: LivePost.site_topic(site_id),
      origin: origin,
      empty: session["empty"],
      ask: nil,
      path: domain_path(origin),
      unavailable: "The posts could not be loaded just now."
    }

  defp list(
         %{"list" => "tool", "site_id" => site_id, "origin" => origin, "tool" => name} = session
       ),
       do: %{
         id: "pb-tool-posts",
         kind: :tool,
         size: Board.ranked_page_size(),
         likes: :thread,
         topic: LivePost.site_topic(site_id),
         origin: origin,
         tool: name,
         empty: session["empty"],
         ask: session["ask"],
         path: tool_path(%{origin: origin}, name),
         unavailable: "The posts could not be loaded just now."
       }

  # Drawn with the page, the list has the page's own posts; joined, it reads
  # them once. Only the rows are kept, in the stream.
  defp first_page(socket, %{kind: :home}) do
    socket = assign_new(socket, :reports, &home_posts/0)
    {assign(socket, :reports, nil), socket.assigns.reports}
  end

  defp first_page(socket, list) do
    socket = assign_new(socket, :posts, fn -> board_posts(list) end)
    {assign(socket, :posts, nil), socket.assigns.posts}
  end

  defp home_posts do
    with {:ok, filters} <- Discussions.filters(%{}),
         {:ok, posts, _next} <- Discussions.page(filters, nil) do
      posts
    else
      {:error, failure} -> failed(failure)
    end
  end

  defp board_posts(list) do
    with {:ok, site} <- Board.fetch_site(list.origin),
         {:ok, posts, _next} <- list_posts(list, site) do
      posts
    else
      {:error, failure} -> failed(failure)
      :error -> failed(:no_site)
    end
  end

  defp list_posts(%{kind: :site}, site), do: Board.site_threads(site, nil, nil)
  defp list_posts(%{kind: :tool, tool: name}, site), do: Board.ranked_posts(site, name, nil)

  # A tool's list takes only the posts about its tool.
  defp fits?(%{kind: :tool, tool: name}, row), do: name in row.tool_names
  defp fits?(_list, _row), do: true

  # A read that fails as the list joins is logged by its kind only.
  defp failed(failure) do
    Logger.warning("A post list could not be read: " <> inspect(Board.failure_kind(failure)))
    :unavailable
  end

  defp follow(id),
    do: :ok = Phoenix.PubSub.subscribe(Regents.PubSub, LivePost.post_topic(id))

  defp unfollow(id),
    do: :ok = Phoenix.PubSub.unsubscribe(Regents.PubSub, LivePost.post_topic(id))
end
