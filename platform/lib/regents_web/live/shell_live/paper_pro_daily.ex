defmodule RegentsWeb.ShellLive.PaperProDaily do
  @moduledoc """
  Paper Pro Daily: research papers by day with ChatGPT's reading of each, newest
  day first, loading more days as the reader scrolls. Choosing tags narrows the
  feed to the papers filed under any of them, kept in the address (`?tags=`) so a
  filtered list can be shared. The feed is read when the page opens and again at
  each UTC midnight while it stays open, and let go when the page is left.
  """

  import Phoenix.Component, only: [assign: 2]

  import Phoenix.LiveView,
    only: [connected?: 1, push_event: 3, push_patch: 2, stream: 3, stream: 4]

  alias Regents.PaperProDaily
  alias Regents.PaperProDaily.{Publication, Tag}
  alias RegentsWeb.PaperProDaily.{Feed, Reading}

  @page_size 6
  @events ~w(load_more toggle_research_list filter_papers)

  def handles?(event), do: event in @events

  def init(socket),
    do: socket |> assign(paper_midnight: nil) |> cleared()

  # A link to one paper goes to it within the feed; moving between papers keeps the
  # feed as it is, so the reader's place and open papers stay.
  def route(socket, %{route_id: :paper_pro_daily}) do
    socket
    |> read_feed(Reading.chosen_tags(socket.assigns.route_params))
    |> follow_midnight()
    |> go_to_paper(socket.assigns.route_params["paper"])
  end

  def route(socket, _route_spec), do: socket |> forget_midnight() |> cleared()

  # Midnight on the page: the new day's papers, and the next midnight after them.
  def midnight(%{assigns: %{route_spec: %{route_id: :paper_pro_daily}}} = socket),
    do: socket |> refresh_papers() |> follow_midnight()

  def midnight(socket), do: socket

  def handle_event("load_more", _params, socket) do
    # A scroll event can reach us before the midnight timer. Reset the old offset
    # rather than duplicating or skipping a day when a new day is inserted above it.
    if socket.assigns.publication_date == Date.utc_today(),
      do: show_more(socket),
      else: refresh_papers(socket)
  end

  def handle_event("filter_papers", %{"tag" => tag}, socket) do
    chosen = socket.assigns.paper_tags
    tags = Enum.filter(Tag.values(), &(&1 == tag != &1 in chosen))
    push_patch(socket, to: "/paper-pro-daily" <> Reading.tags_query(tags))
  end

  def handle_event("toggle_research_list", _params, socket),
    do: assign(socket, research_list_expanded?: !socket.assigns.research_list_expanded?)

  @doc "The paper a link names, or a 404 when it names none that is published."
  def linked_paper!(%{"paper" => anchor}) do
    PaperProDaily.get_paper_by_anchor!(anchor) || raise RegentsWeb.NotFoundError
  end

  defp go_to_paper(socket, nil), do: socket

  # A paper outside the chosen tags is not in the list, so the page stays where it is.
  defp go_to_paper(socket, target) do
    case Enum.find(socket.assigns.research_list, &(&1.target == target)) do
      nil ->
        socket

      paper ->
        missing =
          Enum.find_index(socket.assigns.days, &(&1 == paper.date)) + 1 - socket.assigns.shown

        socket = if missing > 0, do: show_more(socket, missing), else: socket
        push_event(socket, "paper-daily:go-to-paper", %{target: target})
    end
  end

  defp read_feed(%{assigns: %{days: [_ | _], paper_tags: tags}} = socket, tags), do: socket
  defp read_feed(socket, tags), do: socket |> assign(paper_tags: tags) |> refresh_papers()

  defp cleared(socket) do
    socket
    |> assign(
      research_list_expanded?: false,
      paper_tags: [],
      publication_date: nil,
      days: [],
      shown: 0,
      more?: false,
      research_list: []
    )
    |> stream(:days, [], reset: true)
  end

  defp refresh_papers(socket) do
    papers = Reading.filed_under(Feed.outline(), socket.assigns.paper_tags)

    socket
    |> assign(
      publication_date: Date.utc_today(),
      days: papers |> Enum.map(& &1.date) |> Enum.dedup(),
      shown: 0,
      more?: false,
      research_list:
        Enum.map(papers, &%{title: &1.title, date: &1.date, target: Reading.anchor(&1)})
    )
    |> stream(:days, [], reset: true)
    |> show_more()
  end

  # One timer at a time: a page opened again, or a midnight that has just
  # passed, replaces the one before.
  defp follow_midnight(socket) do
    if connected?(socket) do
      socket = forget_midnight(socket)

      timer =
        Process.send_after(
          self(),
          :publication_midnight,
          Publication.milliseconds_until_midnight()
        )

      assign(socket, paper_midnight: timer)
    else
      socket
    end
  end

  defp forget_midnight(%{assigns: %{paper_midnight: nil}} = socket), do: socket

  defp forget_midnight(socket) do
    Process.cancel_timer(socket.assigns.paper_midnight)
    assign(socket, paper_midnight: nil)
  end

  # The next days in the feed, each with its papers under the chosen tags.
  defp show_more(socket, count \\ @page_size) do
    %{days: days, shown: shown, paper_tags: tags} = socket.assigns
    dates = Enum.slice(days, shown, count)

    socket
    |> stream(
      :days,
      Enum.map(Feed.days(dates), &%{&1 | papers: Reading.filed_under(&1.papers, tags)})
    )
    |> assign(shown: shown + length(dates), more?: shown + length(dates) < length(days))
  end
end
