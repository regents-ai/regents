defmodule Regents.PaperProDailyFixtures do
  @moduledoc "Paper fixtures written with the same system-only action as the release command."

  alias Regents.Actors.System
  alias Regents.PaperProDaily

  def paper_fixture!(date, attrs \\ %{}) do
    %{
      date: date,
      title: "Paper #{date}",
      arxiv_url: "https://arxiv.org/abs/2610.04074",
      chatgpt_url: "https://chatgpt.com/share/paper-test-#{date}",
      author: "Test author",
      answer: "Research answer for #{date}.",
      picture:
        Base.decode64!(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO/aF1cAAAAASUVORK5CYII="
        ),
      picture_type: "image/png",
      picture_alt: "Cover for #{date}"
    }
    |> Map.merge(attrs)
    |> PaperProDaily.put_paper!(actor: %System{})
  end
end
