defmodule AshPlatform.Discussions.MarkdownTest do
  use ExUnit.Case, async: true

  alias AshPlatform.Discussions.Markdown

  test "normalizes allowed Markdown and renders only the restricted vocabulary" do
    body = "  Useful **evidence**\r\n\r\n- [Source](https://example.com)\r\n- `code`  "

    assert {:ok, normalized} = Markdown.normalize_and_validate(body)
    assert normalized == "Useful **evidence**\n\n- [Source](https://example.com)\n- `code`"

    html = Markdown.to_safe_html(normalized) |> Phoenix.HTML.safe_to_string()
    assert html =~ "<strong>evidence</strong>"
    assert html =~ ~s(href="https://example.com")
    assert html =~ ~s(rel="noopener noreferrer")
    assert html =~ "<code>code</code>"
  end

  test "counts normalized user-perceived graphemes" do
    family = "👨‍👩‍👧‍👦"
    assert {:ok, _body} = Markdown.normalize_and_validate(String.duplicate(family, 2_000))
    assert {:error, :too_long} = Markdown.normalize_and_validate(String.duplicate(family, 2_001))
  end

  test "rejects disallowed structures and unsafe links" do
    for body <- [
          "# Heading",
          "![image](https://example.com/image.png)",
          "<b>raw html</b>",
          "| table |\n| --- |\n| cell |",
          "[unsafe](javascript:alert(1))",
          "[relative](/private)"
        ] do
      assert {:error, :unsupported_markdown} = Markdown.normalize_and_validate(body), body
    end
  end

  test "rejects an empty normalized comment" do
    assert {:error, :empty} = Markdown.normalize_and_validate(" \r\n ")
  end
end
