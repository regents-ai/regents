defmodule RegentsWeb.Techtree.PublicPagesHTML do
  @moduledoc """
  Security's sample report in Techtree's document layout, from its committed
  Markdown (`priv/techtree/public/services/security-sample-report.md`).
  """

  use RegentsWeb, :html

  import Phoenix.HTML, only: [raw: 1]

  alias RegentsWeb.Techtree.Layouts

  @pages %{
    "/techtree/services/security/sample-report" => "services/security-sample-report"
  }

  @doc """
  The page at `path` split for its layout: the title, the one-paragraph lede
  under it, and the rest rendered as HTML. Any other address, such as one the
  router reads as the page's but spelled differently, is a missing page.
  """
  @spec page(String.t()) :: %{title: String.t(), lede: String.t(), body_html: String.t()}
  for {path, name} <- @pages do
    source = Application.app_dir(:regents, "priv/techtree/public/#{name}.md")
    @external_resource source
    ["# " <> title, lede, body] = source |> File.read!() |> String.split("\n\n", parts: 3)
    {body_html, _contents} = RegentBlog.markdown(body)

    def page(unquote(path)),
      do: %{title: unquote(title), lede: unquote(lede), body_html: unquote(body_html)}
  end

  def page(_path), do: raise(RegentsWeb.NotFoundError)

  attr :page, :map, required: true

  # page/1 renders only committed Markdown; no request HTML enters it.
  # sobelow_skip ["XSS.Raw"]
  def show(assigns) do
    ~H"""
    <Layouts.page>
      <header class="editorial-heading">
        <h1>{@page.title}</h1>
        <p class="lede">{@page.lede}</p>
      </header>
      <article class="public-document rg-blog__prose">
        {raw(@page.body_html)}
      </article>
    </Layouts.page>
    """
  end
end
