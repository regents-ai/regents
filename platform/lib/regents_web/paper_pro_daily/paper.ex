defmodule RegentsWeb.PaperProDaily.Paper do
  @moduledoc "Reads one day's paper file for `RegentsWeb.PaperProDaily`, raising when it breaks the rules."

  @images Application.app_dir(:regents, "priv/static/images/paper-pro-daily")
  @keys ~w(title arxiv_url chatgpt_url image image_alt)
  @excerpt_words 100
  @extension [table: true, strikethrough: true, math_dollars: true]

  def read!(path) do
    with {:ok, date} <- path |> Path.basename(".md") |> Date.from_iso8601(),
         [_, front, markdown] <-
           Regex.run(
             ~r/\A---\n(.*?)\n---\n(.*)\z/s,
             File.read!(path) |> String.replace("\r\n", "\n")
           ),
         {:ok, %{} = meta} <- YamlElixir.read_from_string(front),
         [] <- Map.keys(meta) -- @keys,
         [] <- @keys -- Map.keys(meta),
         true <- Enum.all?(Map.values(meta), &(is_binary(&1) and String.trim(&1) != "")),
         true <-
           Regex.match?(
             ~r{\Ahttps://arxiv\.org/(?:abs|pdf)/[A-Za-z0-9.\-/]+\z},
             meta["arxiv_url"]
           ),
         true <-
           Regex.match?(~r{\Ahttps://chatgpt\.com/share/[A-Za-z0-9\-]+\z}, meta["chatgpt_url"]),
         true <- Regex.match?(~r/\A[a-z0-9][a-z0-9\-]*\.(?:webp|png|jpg|jpeg)\z/, meta["image"]),
         {:ok, %{type: :regular, size: size}} when size <= 1_000_000 <-
           File.lstat(Path.join(@images, meta["image"])),
         true <- String.trim(markdown) != "" do
      document = markdown |> MDEx.parse_document!(extension: @extension) |> demote_headings()
      {excerpt, _words_left} = excerpt(document.nodes, @excerpt_words)

      %{
        id: Date.to_iso8601(date),
        date: date,
        title: meta["title"],
        arxiv_url: meta["arxiv_url"],
        chatgpt_url: meta["chatgpt_url"],
        image: "/images/paper-pro-daily/" <> meta["image"],
        image_alt: meta["image_alt"],
        html: html(document),
        excerpt_html: html(%{document | nodes: excerpt}),
        more?: excerpt != document.nodes
      }
    else
      _ ->
        raise ArgumentError,
              "#{path}: expected a <YYYY-MM-DD>.md name, front matter with exactly #{Enum.join(@keys, ", ")}, " <>
                "an arxiv.org link, a chatgpt.com/share link, an image of at most 1 MB in " <>
                "priv/static/images/paper-pro-daily/, and the answer in Markdown"
    end
  end

  # Each paper's title is a level-two heading, so the answer's headings start at level three.
  defp demote_headings(%MDEx.Heading{} = heading),
    do: %{
      heading
      | level: min(max(heading.level + 1, 3), 6),
        nodes: Enum.map(heading.nodes, &demote_headings/1)
    }

  defp demote_headings(%{nodes: nodes} = node),
    do: %{node | nodes: Enum.map(nodes, &demote_headings/1)}

  defp demote_headings(node), do: node

  # The opening words of the answer, keeping its formatting: everything up to the
  # hundredth word, cut there with an ellipsis. Maths and code count as one word each.
  defp excerpt(nodes, budget) do
    {kept, budget} =
      Enum.reduce_while(nodes, {[], budget}, fn
        _node, {kept, 0} ->
          {:halt, {kept, 0}}

        %MDEx.Text{literal: literal} = text, {kept, budget} ->
          case Regex.scan(~r/\S+/u, literal, return: :index) do
            words when length(words) <= budget ->
              {:cont, {[text | kept], budget - length(words)}}

            words ->
              [{start, length}] = Enum.at(words, budget - 1)
              cut = binary_part(literal, 0, start + length) <> "…"
              {:halt, {[%{text | literal: cut} | kept], 0}}
          end

        %{nodes: children} = node, {kept, budget} ->
          {children, budget} = excerpt(children, budget)
          {:cont, {[%{node | nodes: children} | kept], budget}}

        %{literal: _} = leaf, {kept, budget} ->
          {:cont, {[leaf | kept], budget - 1}}

        node, {kept, budget} ->
          {:cont, {[node | kept], budget}}
      end)

    {Enum.reverse(kept), budget}
  end

  defp html(document), do: MDEx.to_html!(document, extension: @extension, render: [unsafe: false])
end
