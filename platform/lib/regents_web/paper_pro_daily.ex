defmodule RegentsWeb.PaperProDaily do
  @moduledoc """
  The papers on /paper-pro-daily, newest first, compiled from
  `priv/paper_pro_daily/<YYYY-MM-DD>.md`: one file a day, named by its date.

  Each file is YAML front matter (`title`, `arxiv_url`, `chatgpt_url`, `image`,
  `image_alt`) followed by ChatGPT's answer in Markdown. `image` names a file in
  `priv/static/images/paper-pro-daily/`. A file that breaks these rules stops the
  build, so a release never shows a broken paper.
  """

  @root Application.app_dir(:regents, "priv/paper_pro_daily")
  @paths Path.wildcard(Path.join(@root, "*.md")) |> Enum.sort()
  for path <- @paths, do: @external_resource(path)

  @papers @paths
          |> Enum.map(&RegentsWeb.PaperProDaily.Paper.read!/1)
          |> Enum.sort_by(& &1.date, {:desc, Date})

  @doc "Up to `limit` papers, newest first, after skipping `offset`."
  def page(offset, limit), do: Enum.slice(@papers, offset, limit)

  def count, do: length(@papers)

  def __mix_recompile__?, do: Enum.sort(Path.wildcard(Path.join(@root, "*.md"))) != @paths
end
