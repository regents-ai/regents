defmodule RegentsWeb.SiwaLive do
  @moduledoc """
  The `/siwa` page (also rendered at `/docs/siwa`): Sign-in with Agent (SIWA)
  across Regents Labs — pairing, request signing, Hello Cards, ERC-8004
  registration, World AgentBook backing, and external site integration.
  The page and its Markdown version (`markdown/0`) derive from the same words.
  """
  use RegentsWeb, :html

  @heading "SIWA"

  @lede "Sign-in with Agent (SIWA) lets an agent prove its identity with its own key across every Regents Labs product — no API keys, no wallet balance, and no shared browser cookies."

  @sections [
    %{
      title: "Pairing and check-in",
      paragraphs: [
        "A person creates a one-time pairing code with Pair New Agent on their Agents page (/account/agents) and hands it to their agent. The agent exchanges that code once with its own SIWA key via POST /api/agents/v1/pair, then checks in via GET /api/agents/v1/me.",
        "Every signed request uses fresh HTTP message signatures verified through https://siwa.regents.sh for audience `regents`. Account owners see their paired agents, latest contact timestamp, and daily site activity summaries on /account/agents."
      ]
    },
    %{
      title: "Hello Cards, ERC-8004, and World AgentBook",
      paragraphs: [
        "Once paired on regents.sh, an agent can request a signed Hello Card from siwa.regents.sh and attach it in the `x-siwa-hello-card` header to prove it is paired with a real person here without exposing private account details.",
        "Agents can also link an ERC-8004 onchain registry listing and World ID AgentBook backing so platforms know a verified human stands behind the agent and how many agents share that backing."
      ]
    },
    %{
      title: "Using SIWA on your own website",
      paragraphs: [
        "External websites can verify SIWA agent signatures through https://siwa.regents.sh using the starter SDKs (`siwa-site.mjs` and `siwa-site.py`) and try the end-to-end flow on the live demo at https://demo.regents.sh."
      ]
    }
  ]

  @links [
    %{label: "Pairing guide", href: "/docs/pairing", primary: true, external: false},
    %{label: "Hosted MCP", href: "/docs/mcp", primary: false, external: false},
    %{
      label: "Agent skill (siwa.regents.sh)",
      href: "https://siwa.regents.sh/skill.md",
      primary: false,
      external: true
    },
    %{
      label: "Website integration",
      href: "https://siwa.regents.sh/websites.md",
      primary: false,
      external: true
    },
    %{label: "Live demo", href: "https://demo.regents.sh", primary: false, external: true}
  ]

  def page(assigns) do
    assigns = assign(assigns, heading: @heading, lede: @lede, sections: @sections, links: @links)

    ~H"""
    <section id="siwa-page" class="product-page" aria-labelledby="product-heading">
      <header class="product-heading rg-panel rg-panel--surface rg-panel__body">
        <h1 id="product-heading" tabindex="-1">{@heading}</h1>
        <p class="product-lede">{@lede}</p>
        <div class="product-actions">
          <a
            :for={link <- @links}
            class={if link.primary, do: "rg-button rg-button--primary", else: "rg-button"}
            href={link.href}
            target={if link.external, do: "_blank"}
            rel={if link.external, do: "noopener noreferrer"}
          >
            <span class="rg-button__label">{link.label}</span>
          </a>
        </div>
      </header>
      <div class="product-sections">
        <section :for={section <- @sections} class="rg-panel rg-panel--surface rg-panel__body">
          <h2>{section.title}</h2>
          <p :for={paragraph <- section.paragraphs}>{paragraph}</p>
        </section>
      </div>
    </section>
    """
  end

  @doc "The page as Markdown, what `/siwa` and `/docs/siwa` render."
  def markdown do
    body =
      Enum.map_join(@sections, "\n\n", fn section ->
        "## #{section.title}\n\n" <> Enum.join(section.paragraphs, "\n\n")
      end)

    refs =
      Enum.map_join(@links, "\n", fn link ->
        "- [#{link.label}](#{link.href})"
      end)

    """
    # #{@heading}

    #{@lede}

    #{body}

    ## Resources

    #{refs}
    """
  end
end
