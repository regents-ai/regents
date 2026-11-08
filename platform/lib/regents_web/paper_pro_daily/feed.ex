defmodule RegentsWeb.PaperProDaily.Feed do
  @moduledoc """
  What /paper-pro-daily shows, kept on this machine for a minute and shared by
  every open of the page, so a crowd of readers costs the database one read a
  minute, and a reader's first load and live connection cost one between them.

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

  @doc "Every published paper's id, date, title and tags, newest day first."
  def outline, do: kept(:outline, &PaperProDaily.paper_outline!/0)

  @doc "The given days, each with all of its papers ready to show."
  def days(dates) do
    kept({:days, dates}, fn ->
      dates
      |> PaperProDaily.list_papers!()
      |> Enum.chunk_by(& &1.date)
      |> Enum.map(
        &%{id: Date.to_iso8601(hd(&1).date), papers: Enum.map(&1, fn paper -> shown(paper) end)}
      )
    end)
  end

  @doc "All published papers as one Markdown page, or only those under any of the chosen tags."
  def page_markdown([]) do
    kept(:page_markdown, fn -> Reading.page_markdown(PaperProDaily.export_papers!()) end)
  end

  def page_markdown(tags) do
    kept({:page_markdown, tags}, fn ->
      PaperProDaily.export_papers!()
      |> Reading.filed_under(tags)
      |> Reading.filtered_markdown(tags)
    end)
  end

  defp kept(name, read), do: get_or_store!({Date.utc_today(), name}, read, ttl: @kept)

  # The picture's address changes whenever the paper is saved again, so a browser
  # may keep each one for good.
  defp shown(paper) do
    paper
    |> Map.take([
      :id,
      :date,
      :title,
      :authors,
      :arxiv_url,
      :chatgpt_url,
      :author,
      :picture_alt,
      :tags
    ])
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
