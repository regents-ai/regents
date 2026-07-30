defmodule AshPlatform.Discussions.Markdown do
  @moduledoc false

  @allowed_nodes MapSet.new([
                   MDEx.Document,
                   MDEx.Paragraph,
                   MDEx.Text,
                   MDEx.SoftBreak,
                   MDEx.LineBreak,
                   MDEx.Emph,
                   MDEx.Strong,
                   MDEx.Code,
                   MDEx.CodeBlock,
                   MDEx.List,
                   MDEx.ListItem,
                   MDEx.Link,
                   MDEx.Escaped
                 ])

  @sanitize [
    tags: ~w(p a em strong code pre ul ol li br),
    tag_attributes: %{"a" => ["href"], "code" => ["class"]},
    generic_attributes: [],
    url_schemes: ~w(http https),
    url_relative: :deny,
    link_rel: "noopener noreferrer"
  ]
  @parse_options [extension: [table: true]]

  def normalize_and_validate(body) when is_binary(body) do
    normalized =
      body
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.normalize(:nfc)
      |> String.trim()

    cond do
      normalized == "" ->
        {:error, :empty}

      String.length(normalized) > 2_000 ->
        {:error, :too_long}

      true ->
        validate_document(normalized)
    end
  end

  def normalize_and_validate(_body), do: {:error, :invalid}

  # Both raw calls receive only allowlisted, MDEx-sanitized HTML or a fixed empty string.
  # sobelow_skip ["XSS.Raw"]
  def to_safe_html(body) do
    with {:ok, normalized} <- normalize_and_validate(body),
         {:ok, document} <- MDEx.parse_document(normalized, @parse_options) do
      document
      |> MDEx.to_html!(sanitize: @sanitize)
      |> Phoenix.HTML.raw()
    else
      _ -> Phoenix.HTML.raw("")
    end
  end

  defp validate_document(normalized) do
    with {:ok, document} <- MDEx.parse_document(normalized, @parse_options),
         true <- Enum.all?(document, &allowed_node?/1),
         true <- Enum.all?(document, &safe_link?/1) do
      {:ok, normalized}
    else
      _ -> {:error, :unsupported_markdown}
    end
  end

  defp allowed_node?(%module{}), do: MapSet.member?(@allowed_nodes, module)

  defp safe_link?(%MDEx.Link{url: url}) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _ ->
        false
    end
  end

  defp safe_link?(_node), do: true
end
