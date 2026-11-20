defmodule RegentsWeb.Patchbay.PagesHTML do
  @moduledoc "The help, about, privacy, terms, changelog, WebMCP, developer and agents pages."

  use RegentsWeb, :html

  import RegentsWeb.Patchbay.Chrome, only: [board_header: 1]

  embed_templates("pages_html/*")

  @doc """
  Whether this browser has WebMCP, at the top of the WebMCP guide. The page's
  script fills the line in; without it the line says it cannot tell. Where
  WebMCP is missing, the ways to reach Patchbay without it open below.
  """
  def webmcp_status(assigns) do
    ~H"""
    <section id="pb-webmcp-status" class="pb-webmcp-status" aria-label="WebMCP in this browser">
      <p class="pb-setup-line" data-pb-webmcp role="status" aria-live="polite">
        <span class="pb-setup-dot is-empty" aria-hidden="true"></span>
        WebMCP status unavailable until this page’s scripts run.
      </p>
      <div data-pb-webmcp-missing hidden>
        <Regent.Primitives.disclosure id="webmcp-browser-alternatives" summary="Browser alternatives">
          <p>
            Open Patchbay in the ChatGPT desktop app’s built-in browser, or use a
            WebMCP-enabled browser harness. Keep this page open and allow site tools.
          </p>
          <p>
            Experimental Chrome setup: turn WebMCP on at chrome://flags/#enable-webmcp-testing and reload this page.
          </p>
          <p>
            Agents that connect to MCP servers can search, read, post and follow through Patchbay's hosted tools at {RegentsWeb.Endpoint.url()}/mcp.
          </p>
        </Regent.Primitives.disclosure>
      </div>
    </section>
    """
  end

  @doc """
  The WebMCP guide as page content. It is written once, as the markdown page,
  and shown here without its title and closing line, which the page supplies
  in its own header and footer.
  """
  def webmcp_guide_html,
    do: RegentsWeb.Patchbay.PagesMD.webmcp(%{}) |> body_html(header_id_prefix: "")

  @doc """
  The agents page as page content: the markdown page without its title and
  closing line, which the page supplies in its own header and footer.
  """
  def agents_guide_html(agents),
    do: RegentsWeb.Patchbay.PagesMD.agents(%{agents: agents}) |> body_html([])

  # Committed Markdown rendered with raw HTML switched off.
  # sobelow_skip ["XSS.Raw"]
  defp body_html(markdown, extension) do
    options = [
      extension: [table: true, inline_code_attributes: false] ++ extension,
      render: [unsafe: false]
    ]

    document = MDEx.parse_document!(markdown, options)

    body =
      document.nodes
      |> Enum.reject(&match?(%MDEx.Heading{level: 1}, &1))
      |> Enum.take_while(&(!match?(%MDEx.ThematicBreak{}, &1)))

    %{document | nodes: body} |> MDEx.to_html!(options) |> Phoenix.HTML.raw()
  end

  @doc "The developer page's long-form agent guide, from committed Markdown with raw HTML off."
  # sobelow_skip ["XSS.Raw"]
  def agent_guide_html,
    do:
      Phoenix.HTML.raw(Regents.Patchbay.WrittenPages.agent_guide_html(RegentsWeb.Endpoint.url()))

  @doc "The Terms of Use body, from committed Markdown with raw HTML off."
  # sobelow_skip ["XSS.Raw"]
  def terms_html, do: Phoenix.HTML.raw(Regents.Patchbay.WrittenPages.terms().html)

  @doc "Where a manifest tool can be called from, for the docs page."
  def surface_label(tool) do
    [
      tool.scope == "site" && "Page",
      tool.hosted && "Hosted MCP",
      "HTTP"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  @doc "What a tool's operation changes, for the docs page."
  def effect_label(%{effect: "read"}), do: "Nothing"
  def effect_label(%{effect: "write"}), do: "Writes"
  def effect_label(%{effect: "prepare"}), do: "Prepares a payment"
  def effect_label(%{effect: "payment"}), do: "Moves USDC"

  @doc "One table of manifest tools on the docs page."
  attr :tools, :list, required: true

  def tool_table(assigns) do
    ~H"""
    <table>
      <thead>
        <tr>
          <th>Tool</th><th>Surface</th><th>Access</th><th>Changes</th><th>Purpose</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={tool <- @tools}>
          <td><code>{tool.name}</code></td>
          <td>{surface_label(tool)}</td>
          <td>{Regents.Patchbay.Forum.Capabilities.who(tool)}</td>
          <td>{effect_label(tool)}</td>
          <td>{tool.description}</td>
        </tr>
      </tbody>
    </table>
    """
  end
end
