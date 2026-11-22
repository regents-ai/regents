defmodule RegentsWeb.PaperProDaily.Feed do
  @moduledoc """
  What /paper-pro-daily shows, kept on this machine for a minute and shared by
  every open of the page, so a crowd of readers costs the database one read a
  minute, and a reader's first load and live connection cost one between them.

  Each day is kept by itself, so a link to an older paper reads and renders only
  the days not kept yet. One request at a time reads and renders days: any other
  that needs days waits for it, then takes what it kept.

  `Regents.Release.put_paper` clears what is kept as it saves, so a new paper shows at
  once. What is kept lives on one machine: regents.sh runs one, and a second machine
  would show a new paper up to a minute later.
  Each reading is kept under the UTC day, so a day's papers appear as soon as that
  day begins.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  alias Regents.PaperProDaily
  alias RegentsWeb.PaperProDaily.Reading

  @kept :timer.minutes(1)

  @doc "Every published paper's id, date and title, newest day first."
  def outline, do: kept(:outline, &PaperProDaily.paper_outline!/0)

  @doc "The given days in the order given, each with all of its papers ready to show."
  def days(dates) do
    kept = kept_days(dates)
    days = if Enum.all?(dates, &Map.has_key?(kept, &1)), do: kept, else: keep_days(dates)

    dates
    |> Enum.map(&Map.fetch!(days, &1))
    |> Enum.reject(&(&1.papers == []))
  end

  @doc "All published papers as one Markdown page."
  def page_markdown do
    kept(:page_markdown, fn -> Reading.page_markdown(PaperProDaily.export_papers!()) end)
  end

  defp kept(name, read), do: get_or_store!(key(name), read, ttl: @kept)

  defp key(name), do: {Date.utc_today(), name}

  defp kept_days(dates) do
    [in: Enum.map(dates, &key({:day, &1}))]
    |> get_all!()
    |> Map.new(fn {{_today, {:day, date}}, day} -> {date, day} end)
  end

  # Under the lock the days are looked up again: the request that held it before
  # may have kept them. A request waits as long as the lock is held, rather than
  # failing after the three short tries Nebulex makes by default.
  defp keep_days(dates) do
    {:ok, days} =
      transaction(
        fn ->
          kept = kept_days(dates)
          dates |> Enum.reject(&Map.has_key?(kept, &1)) |> read_days() |> Map.merge(kept)
        end,
        keys: [:days],
        retries: :infinity
      )

    days
  end

  defp read_days([]), do: %{}

  # A day without papers is kept too, with none to show.
  defp read_days(dates) do
    papers = dates |> PaperProDaily.list_papers!() |> Enum.group_by(& &1.date, &shown/1)
    days = Map.new(dates, &{&1, %{id: Date.to_iso8601(&1), papers: Map.get(papers, &1, [])}})
    put_all!(Map.new(days, fn {date, day} -> {key({:day, date}), day} end), ttl: @kept)
    days
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
      markdown: Reading.details_markdown(paper),
      anchor: Reading.anchor(paper),
      url: Reading.url(paper)
    })
  end
end
