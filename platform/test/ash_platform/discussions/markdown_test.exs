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

  test "renders Markdown structures and preserves escaped LaTeX for the math renderer" do
    body = ~S"""
    ## Results

    > A **useful** result with ~~old~~ text.

    | Input | Result |
    | --- | --- |
    | `x` | 2 |

    Inline $x^2$ and display $$\frac{1}{2}$$.
    """

    assert {:ok, _} = Markdown.normalize_and_validate(body)
    html = body |> Markdown.to_safe_html() |> Phoenix.HTML.safe_to_string()

    for tag <- [
          "<h2>",
          "<blockquote>",
          "<del>",
          "<table>",
          ~s(data-math-style="inline"),
          ~s(data-math-style="display")
        ],
        do: assert(html =~ tag)

    assert html =~ ~S(\frac{1}{2})

    escaped =
      ~S|$\text{<img src=x onerror=alert(1)>}$|
      |> Markdown.to_safe_html()
      |> Phoenix.HTML.safe_to_string()

    refute escaped =~ "<img"
    assert escaped =~ "&lt;img"
  end

  test "math inside code and escaped dollar signs stay literal" do
    for body <- [~S(`$x^2$`), "```elixir\n$x^2$\n```", ~S(Price \$5)] do
      html = body |> Markdown.to_safe_html() |> Phoenix.HTML.safe_to_string()
      refute html =~ "data-math-style"
      assert html != ""
    end
  end

  test "counts normalized user-perceived graphemes" do
    family = "👨‍👩‍👧‍👦"
    assert {:ok, _body} = Markdown.normalize_and_validate(String.duplicate(family, 2_000))
    assert {:error, :too_long} = Markdown.normalize_and_validate(String.duplicate(family, 2_001))
  end

  test "rejects disallowed structures and unsafe links" do
    for body <- [
          "![image](https://example.com/image.png)",
          "<b>raw html</b>",
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
