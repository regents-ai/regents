defmodule Regents.Blog.PostFile do
  @moduledoc "Reads post.md and exactly one cover image from an operator-owned folder."
  @keys ~w(slug title description date author author_x cover_alt draft)

  # sobelow_skip ["Traversal.FileModule"]
  def read!(folder) do
    path = Path.join(folder, "post.md")
    source = read_bounded!(path) |> String.replace("\r\n", "\n")

    with [_, front, markdown] <- Regex.run(~r/\A---\n(.*?)\n---\n(.*)\z/s, source),
         {:ok, %{} = meta} <- YamlElixir.read_from_string(front),
         [] <- Map.keys(meta) -- @keys do
      if String.trim(markdown) == "", do: raise(ArgumentError, "#{path}: post text is empty")

      attributes = %{
        slug: Map.get(meta, "slug", Path.basename(Path.expand(folder))),
        title: required!(meta, "title"),
        description: Map.get(meta, "description", ""),
        date: date!(required!(meta, "date")),
        author: required!(meta, "author"),
        author_x: required!(meta, "author_x"),
        cover_alt: required!(meta, "cover_alt"),
        draft: Map.get(meta, "draft", false),
        markdown: markdown
      }

      Map.merge(attributes, cover!(folder))
    else
      _ ->
        raise ArgumentError,
              "#{path}: expected a Markdown body and YAML header containing only #{Enum.join(@keys, ", ")}"
    end
  end

  defp required!(meta, key) do
    case Map.get(meta, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: raise(ArgumentError, "#{key} is empty")
        value

      _ ->
        raise ArgumentError, "#{key} must be text"
    end
  end

  defp date!(value) do
    parsed =
      case Regex.run(~r/\A(\d{2})-(\d{2})-(\d{4})\z/, value) do
        [_, month, day, year] ->
          Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))

        _ ->
          Date.from_iso8601(value)
      end

    case parsed do
      {:ok, date} -> date
      _ -> raise ArgumentError, "date must be a valid MM-DD-YYYY or YYYY-MM-DD date"
    end
  end

  defp cover!(folder) do
    paths =
      Enum.map(~w(webp png jpg jpeg), &Path.join(folder, "cover.#{&1}"))
      |> Enum.filter(&File.regular?/1)

    case paths do
      [path] ->
        cover = read_bounded!(path)
        %{cover: cover, cover_type: cover_type!(cover)}

      _ ->
        raise ArgumentError,
              "#{folder}: expected exactly one cover.webp, cover.png, cover.jpg or cover.jpeg"
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_bounded!(path) do
    if File.stat!(path).size > 1_000_000, do: raise(ArgumentError, "#{path}: exceeds 1 MB")
    File.read!(path)
  end

  @doc "Detects the supported image format from its bytes, rather than its filename."
  def cover_type!(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: "image/png"
  def cover_type!(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  def cover_type!(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  def cover_type!(_), do: raise(ArgumentError, "cover must be a PNG, JPEG or WebP image")
end
