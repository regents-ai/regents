defmodule Regents.PaperProDaily.PaperFile do
  @moduledoc """
  Reads one day's paper from a folder, or the original two-file upload format.

  A folder contains `paper.md` with `title`, `date` (MM-DD-YYYY), `paper_url`,
  `chatgpt_url`, `chatgpt_model` and optional `cover_alt` in its YAML header,
  followed by the answer in Markdown, and one `cover.webp`, PNG or JPEG.

  The original paper is `<YYYY-MM-DD>.md`, named by its day: YAML front matter (`title`,
  `arxiv_url`, `chatgpt_url`, `author`, `picture_alt`), then ChatGPT's answer in
  Markdown. The picture is a WebP, PNG or JPEG file. The paper's own rules, such
  as its links and the picture's size, are checked when it is saved.
  """

  @keys ~w(title arxiv_url chatgpt_url author picture_alt)
  @folder_keys ~w(title date paper_url chatgpt_url chatgpt_model cover_alt)

  @doc "Reads paper.md and exactly one cover.webp, cover.png, cover.jpg or cover.jpeg."
  # sobelow_skip ["Traversal.FileModule"]
  def read!(folder) do
    paper_path = Path.join(folder, "paper.md")
    {meta, answer} = metadata!(paper_path, @folder_keys)
    title = required!(meta, "title", paper_path)

    covers =
      Enum.filter(~w(webp png jpg jpeg), &File.regular?(Path.join(folder, "cover.#{&1}")))

    picture_path =
      case covers do
        [extension] ->
          Path.join(folder, "cover.#{extension}")

        _ ->
          raise ArgumentError,
                "#{folder}: expected exactly one cover.webp, cover.png, cover.jpg or cover.jpeg"
      end

    %{
      title: title,
      date: date!(required!(meta, "date", paper_path), paper_path),
      arxiv_url: required!(meta, "paper_url", paper_path),
      chatgpt_url: required!(meta, "chatgpt_url", paper_path),
      author: required!(meta, "chatgpt_model", paper_path),
      picture_alt: Map.get(meta, "cover_alt", "Cover for #{title}"),
      answer: answer
    }
    |> Map.merge(picture!(picture_path))
  end

  # The paths are the operator's own arguments on the machine they are signed in to.
  # sobelow_skip ["Traversal.FileModule"]
  def read!(paper_path, picture_path) do
    {meta, answer} = metadata!(paper_path, @keys)

    date =
      case paper_path |> Path.basename(".md") |> Date.from_iso8601() do
        {:ok, date} -> date
        _ -> raise ArgumentError, "#{paper_path}: expected a <YYYY-MM-DD>.md filename"
      end

    meta
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
    |> Map.merge(%{date: date, answer: answer})
    |> Map.merge(picture!(picture_path))
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp metadata!(path, keys) do
    source = path |> File.read!() |> String.replace("\r\n", "\n")

    with [_, front, answer] <- Regex.run(~r/\A---\n(.*?)\n---\n(.*)\z/s, source),
         {:ok, %{} = meta} <- YamlElixir.read_from_string(front),
         [] <- Map.keys(meta) -- keys do
      if String.trim(answer) == "", do: raise(ArgumentError, "#{path}: the paper's text is empty")
      {meta, answer}
    else
      _ ->
        raise ArgumentError,
              "#{path}: expected Markdown with a metadata header containing only #{Enum.join(keys, ", ")}"
    end
  end

  defp required!(meta, key, path) do
    case Map.get(meta, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: raise(ArgumentError, "#{path}: #{key} is empty")
        value

      _ ->
        raise ArgumentError, "#{path}: #{key} must be text"
    end
  end

  defp date!(value, path) do
    with [_, month, day, year] <- Regex.run(~r/\A(\d{2})-(\d{2})-(\d{4})\z/, value),
         {:ok, date} <-
           Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
      date
    else
      _ -> raise ArgumentError, "#{path}: date must be a valid MM-DD-YYYY date"
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp picture!(path) do
    picture = File.read!(path)

    case picture_type(picture) do
      {:ok, type} -> %{picture: picture, picture_type: type}
      _ -> raise ArgumentError, "#{path}: expected a WebP, PNG or JPEG picture"
    end
  end

  defp picture_type(<<0x89, "PNG", _rest::binary>>), do: {:ok, "image/png"}
  defp picture_type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "image/jpeg"}

  defp picture_type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: {:ok, "image/webp"}

  defp picture_type(_picture), do: :error
end
