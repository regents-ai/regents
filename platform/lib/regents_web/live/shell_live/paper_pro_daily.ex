defmodule RegentsWeb.ShellLive.PaperProDaily do
  @moduledoc """
  Paper Pro Daily: research papers by day with ChatGPT's reading of each, newest
  day first, loading more days as the reader scrolls. The feed is read when the
  page opens and again at each UTC midnight while it stays open, and let go when
  the page is left.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3, stream: 3, stream: 4]

  alias Regents.PaperProDaily
  alias Regents.PaperProDaily.Publication
  alias RegentsWeb.PaperProDaily.Reading

  @page_size 6
  @events ~w(load_more toggle_research_list go_to_paper)

  def handles?(event), do: event in @events

  def init(socket),
    do: socket |> assign(paper_midnight: nil) |> cleared()

  def route(socket, %{route_id: :paper_pro_daily}),
    do: socket |> refresh_papers() |> follow_midnight()

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

  def handle_event("toggle_research_list", _params, socket),
    do: assign(socket, research_list_expanded?: !socket.assigns.research_list_expanded?)

  def handle_event("go_to_paper", %{"target" => target}, socket) do
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

  defp cleared(socket) do
    socket
    |> assign(
      research_list_expanded?: false,
      publication_date: nil,
      days: [],
      shown: 0,
      more?: false,
      page_markdown: "",
      research_list: []
    )
    |> stream(:days, [], reset: true)
  end

  defp refresh_papers(socket) do
    papers = PaperProDaily.export_papers!()

    socket
    |> assign(
      publication_date: Date.utc_today(),
      days: papers |> Enum.map(& &1.date) |> Enum.dedup(),
      shown: 0,
      more?: false,
      page_markdown: Reading.page_markdown(papers),
      research_list:
        Enum.map(papers, &%{title: &1.title, date: &1.date, target: "paper-#{&1.id}-title"})
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

  # The next days in the feed, each with all of its papers.
  defp show_more(socket, count \\ @page_size) do
    %{days: days, shown: shown} = socket.assigns
    dates = Enum.slice(days, shown, count)

    shown_days =
      dates
      |> PaperProDaily.list_papers!()
      |> Enum.chunk_by(& &1.date)
      |> Enum.map(
        &%{id: Date.to_iso8601(hd(&1).date), papers: Enum.map(&1, fn paper -> shown(paper) end)}
      )

    socket
    |> stream(:days, shown_days)
    |> assign(shown: shown + length(dates), more?: shown + length(dates) < length(days))
  end

  # The picture's address changes whenever the paper is saved again, so a browser
  # may keep each one for good.
  defp shown(paper) do
    paper
    |> Map.take([:id, :date, :title, :authors, :arxiv_url, :chatgpt_url, :author, :picture_alt])
    |> Map.merge(Reading.render(paper.answer))
    |> Map.merge(%{
      picture:
        "/paper-pro-daily/pictures/#{paper.id}?v=#{DateTime.to_unix(paper.updated_at, :microsecond)}",
      markdown: Reading.details_markdown(paper)
    })
  end
end
