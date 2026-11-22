defmodule RegentsWeb.Techtree.PublicPagesHTML do
  @moduledoc """
  Security's sample report in Techtree's document layout, and About and the
  agents' pages under the marketing site's opening band, each from its committed
  Markdown (`priv/techtree/public/`; the agents' through
  `RegentsWeb.Techtree.AgentGuides`).
  """

  use RegentsWeb, :html

  import Phoenix.HTML, only: [raw: 1]
  import RegentsWeb.Techtree.Components.Marketing, only: [opening: 1]

  alias RegentsWeb.Techtree.AgentGuides
  alias RegentsWeb.Techtree.Layouts

  @pages %{
    "/techtree/about" => "about",
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

  # An agent's page names this site's own address, so it is rendered when asked for.
  def page("/techtree/agents" <> _rest = path) do
    case AgentGuides.document(path) do
      %{markdown: markdown} ->
        ["# " <> title, lede, body] = String.split(markdown, "\n\n", parts: 3)
        {body_html, _contents} = RegentBlog.markdown(body)
        %{title: title, lede: lede, body_html: body_html}

      nil ->
        raise RegentsWeb.NotFoundError
    end
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

  attr :page, :map, required: true

  # About, its one line as the band's promise; page/1 renders only committed Markdown.
  # sobelow_skip ["XSS.Raw"]
  def about(assigns) do
    ~H"""
    <Layouts.page wide flush>
      <.opening eyebrow="Company" title={@page.title} line={@page.lede} shape={8} icon="building-2" />
      <section class="mk-section">
        <article class="public-document rg-blog__prose">
          {raw(@page.body_html)}
        </article>
      </section>
    </Layouts.page>
    """
  end

  attr :page, :map, required: true

  # The list of agents or one agent's page; page/1 renders only committed
  # Markdown, filled with this site's own address. Pair opens this site's
  # Agents page, where a person pairs an agent for every product.
  # sobelow_skip ["XSS.Raw"]
  def agent(assigns) do
    ~H"""
    <Layouts.page wide flush>
      <.opening eyebrow="Agents" title={@page.title} line={@page.lede} shape={1} icon="bot">
        <:actions>
          <a href={~p"/account/agents"} class="rg-button rg-button--primary">Pair</a>
        </:actions>
      </.opening>
      <section class="mk-section">
        <article class="public-document rg-blog__prose">
          {raw(@page.body_html)}
        </article>
      </section>
    </Layouts.page>
    """
  end
end
