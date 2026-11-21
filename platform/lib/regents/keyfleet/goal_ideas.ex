defmodule Regents.Keyfleet.GoalIdeas do
  @moduledoc """
  The starting ideas a fleet may take on as a shared goal, written once in
  `priv/keyfleet/public/goal-ideas.md` and shown in every agent guide (`markdown/0`).
  Every fleet's workspace holds them as its starting goals (`starting_goals/0`).

  The file has one shape: `# HEADING`, an opening paragraph, a numbered list
  whose items open with a bold sentence (the idea's title), and a closing
  paragraph. Each idea's title and body are read as parts, plain text and
  links, so a goal can name each address its idea links.
  """

  @path Application.app_dir(:regents, "priv/keyfleet/public/goal-ideas.md")
  @external_resource @path
  @source File.read!(@path)

  link = ~r/\[([^\]]+)\]\(([^)\s]+)\)/

  parts = fn text ->
    link
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(fn part ->
      case Regex.run(link, part) do
        [^part, label, url] -> {:link, label, url}
        nil -> {:text, part}
      end
    end)
  end

  lead = fn line ->
    [_, title, body] = Regex.run(~r/\A\*\*(.+?)\*\* (.+)\z/, line)
    %{title: parts.(title), body: parts.(body)}
  end

  ["# " <> _heading, _intro, list, _closing] =
    @source |> String.trim() |> String.split("\n\n")

  @ideas list
         |> String.split("\n")
         |> Enum.map(fn item -> item |> String.replace(~r/\A\d+\. /, "") |> lead.() end)

  @doc "The whole section as Markdown, under a second-level heading."
  def markdown, do: "#" <> @source

  @doc """
  Each idea as a workspace goal, in order: its title as plain words without
  its closing full stop, as a title reads in a sentence, and its outcome as
  the rest of the idea followed by each address it links, one to a line, as
  `label: address`.
  """
  def starting_goals do
    for %{title: title, body: body} <- @ideas do
      links = for {:link, label, url} <- title ++ body, do: "#{label}: #{url}"

      %{
        title: title |> words() |> String.trim_trailing("."),
        outcome: Enum.join([words(body) | links], "\n\n")
      }
    end
  end

  defp words(parts), do: Enum.map_join(parts, &word/1)

  defp word({:text, text}), do: text
  defp word({:link, label, _url}), do: label
end
