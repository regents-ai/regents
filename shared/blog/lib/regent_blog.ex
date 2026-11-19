defmodule RegentBlog do
  @moduledoc "Validated, file-authored Markdown. No routes, database or runtime filesystem reads."
  @slug ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  def paths(root) do
    unless File.lstat!(root).type == :directory,
      do: raise(ArgumentError, "blog root must be a real directory: #{root}")

    Path.wildcard(Path.join(root, "*.md"))
    |> Enum.reject(&(Path.basename(&1) == "README.md"))
    |> Enum.sort()
  end

  def load!(root) do
    posts = Enum.map(paths(root), &read!/1)

    if length(Enum.uniq_by(posts, & &1.slug)) != length(posts),
      do: raise(ArgumentError, "duplicate blog slug in #{root}")

    Enum.sort_by(posts, &{-Date.to_gregorian_days(&1.date), &1.slug})
  end

  def published(posts, today \\ Date.utc_today()),
    do: Enum.filter(posts, &(not &1.draft and Date.compare(&1.date, today) != :gt))

  def read!(path) do
    %{type: :regular, size: size} = File.lstat!(path)
    if size > 1_000_000, do: raise(ArgumentError, "blog post exceeds 1 MB: #{path}")
    source = File.read!(path) |> String.replace("\r\n", "\n")

    with [_, front, markdown] <- Regex.run(~r/\A---\n(.*?)\n---(?:\n|\z)(.*)\z/s, source),
         {:ok, meta} when is_map(meta) <- YamlElixir.read_from_string(front) do
      title = required!(meta, "title")
      slug = Map.get(meta, "slug", Path.basename(path, ".md"))

      unless is_binary(slug) and Regex.match?(@slug, slug),
        do: raise(ArgumentError, "invalid blog slug: #{path}")

      {:ok, date} = Date.from_iso8601(required!(meta, "date"))
      draft = Map.get(meta, "draft", false)
      unless is_boolean(draft), do: raise(ArgumentError, "draft must be a YAML boolean: #{path}")
      x = required!(meta, "author_x")

      unless Regex.match?(~r/\Ahttps:\/\/(?:x|twitter)\.com\/[A-Za-z0-9_]{1,15}\/?\z/, x),
        do: raise(ArgumentError, "author_x must be an X profile URL: #{path}")

      image = required!(meta, "image")
      unless image_url?(image), do: raise(ArgumentError, "invalid blog image URL: #{path}")
      {html, toc} = markdown(markdown)

      %{
        slug: slug,
        title: title,
        date: date,
        author: required!(meta, "author"),
        author_x: x,
        image: image,
        image_alt: required!(meta, "image_alt"),
        description: Map.get(meta, "description", "") |> text!(),
        draft: draft,
        markdown: String.trim(markdown),
        html: html,
        toc: toc
      }
    else
      _ -> raise ArgumentError, "expected YAML front matter and Markdown: #{path}"
    end
  end

  def markdown(source) do
    html =
      MDEx.to_html!(source,
        extension: [
          table: true,
          strikethrough: true,
          tasklist: true,
          footnotes: true,
          math_dollars: true,
          inline_code_attributes: false
        ],
        render: [unsafe: false]
      )

    nodes = Floki.parse_fragment!(html)
    {nodes, {_ids, toc}} = walk(nodes, {MapSet.new(), []})
    {Floki.raw_html(nodes), Enum.reverse(toc)}
  end

  defp walk(nodes, state) do
    Enum.map_reduce(nodes, state, fn
      {tag, attrs, children}, {ids, toc} when tag in ["h1", "h2", "h3"] ->
        label = Floki.text(children)

        base =
          label
          |> String.downcase()
          |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
          |> String.trim("-")

        # Page shells reserve blog-*; Markdown exclusively owns blog-section-*.
        base = "blog-section-" <> if(base == "", do: "section", else: base)

        id =
          Stream.iterate(1, &(&1 + 1))
          |> Stream.map(&if(&1 == 1, do: base, else: "#{base}-#{&1}"))
          |> Enum.find(&(not MapSet.member?(ids, &1)))

        tag = if tag == "h1", do: "h2", else: tag
        node = {tag, List.keystore(attrs, "id", 0, {"id", id}), children}

        {node,
         {MapSet.put(ids, id),
          [%{id: id, title: label, level: String.to_integer(String.last(tag))} | toc]}}

      {"table", attrs, children}, state ->
        {{"div",
          [
            {"class", "rg-blog-table"},
            {"tabindex", "0"},
            {"role", "region"},
            {"aria-label", "Scrollable table"}
          ], [{"table", attrs, children}]}, state}

      {"pre", attrs, children}, state ->
        {{"pre", [{"tabindex", "0"} | attrs], children}, state}

      {tag, attrs, children}, state ->
        {children, state} = walk(children, state)
        {{tag, attrs, children}, state}

      node, state ->
        {node, state}
    end)
  end

  defp required!(meta, key), do: meta |> Map.fetch!(key) |> text!() |> nonempty!()
  defp text!(value) when is_binary(value), do: value
  defp text!(_), do: raise(ArgumentError, "blog metadata must be text")
  defp nonempty!(""), do: raise(ArgumentError, "blog metadata must not be empty")
  defp nonempty!(value), do: value

  defp image_url?("/images/blog/" <> path),
    do:
      path != "" and Regex.match?(~r/\A[A-Za-z0-9_\/.\-]+\z/, path) and
        not String.contains?(path, "..")

  defp image_url?(_), do: false
end
