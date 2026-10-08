defmodule Regents.PaperProDaily.PaperFile do
  @moduledoc """
  Reads one day's paper from its two files, for `Regents.Release.put_paper/2`.

  The paper is `<YYYY-MM-DD>.md`, named by its day: YAML front matter (`title`,
  `arxiv_url`, `chatgpt_url`, `author`, `picture_alt`), then ChatGPT's answer in
  Markdown. The picture is a WebP, PNG or JPEG file. The paper's own rules, such
  as its links and the picture's size, are checked when it is saved.
  """

  @keys ~w(title arxiv_url chatgpt_url author picture_alt)

  # The paths are the operator's own arguments on the machine they are signed in to.
  # sobelow_skip ["Traversal.FileModule"]
  def read!(paper_path, picture_path) do
    picture = File.read!(picture_path)

    with {:ok, date} <- paper_path |> Path.basename(".md") |> Date.from_iso8601(),
         [_, front, answer] <-
           Regex.run(
             ~r/\A---\n(.*?)\n---\n(.*)\z/s,
             paper_path |> File.read!() |> String.replace("\r\n", "\n")
           ),
         {:ok, %{} = meta} <- YamlElixir.read_from_string(front),
         [] <- Map.keys(meta) -- @keys,
         {:ok, picture_type} <- picture_type(picture) do
      meta
      |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Map.merge(%{date: date, answer: answer, picture: picture, picture_type: picture_type})
    else
      _ ->
        raise ArgumentError,
              "#{paper_path}: expected a <YYYY-MM-DD>.md name, front matter with only " <>
                "#{Enum.join(@keys, ", ")}, then the answer; and #{picture_path}: a WebP, PNG or JPEG picture"
    end
  end

  defp picture_type(<<0x89, "PNG", _rest::binary>>), do: {:ok, "image/png"}
  defp picture_type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "image/jpeg"}

  defp picture_type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: {:ok, "image/webp"}

  defp picture_type(_picture), do: :error
end
