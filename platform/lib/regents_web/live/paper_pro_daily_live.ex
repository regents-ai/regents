defmodule RegentsWeb.PaperProDailyLive do
  @moduledoc "One research paper a day with ChatGPT's reading of it, newest first, loading more as the reader scrolls."
  use RegentsWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Regents.PaperProDaily
  alias RegentsWeb.PaperProDaily.Reading
  alias RegentsWeb.{PublicDocuments, RouteCatalog}

  @page_size 6
  @analysis_prompt """
  Please read and analyze this paper in full: [paper link]

  After your review, write the following responses. Keep your ideas concise and result-backed from the paper.

  1. General ideation on the impact and Importance of the paper
  2. Specific ideation related to the Regents Labs products (regents.sh and related web platforms), and any connections to agentic research, agentic science, agentic commerce, agentic onchain finance, and AI swarms/fleets.
  3. Any negative issues or problems you see in the results, methodology or experiments in the paper.
  4. The next steps you would research or test in order to extend the results of the paper, either new directions of research, or to verify or falsify certain claims.
  5. A conclusion on why this paper matters now in 2026, and what would have to happen for it to become a well-known paper in 2031.

  Be honest in all responses.
  """

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(route_spec: RouteCatalog.fetch!(:paper_pro_daily), shown: 0, more?: false)
     |> assign(
       page_markdown: Reading.page_markdown(PaperProDaily.export_papers!()),
       analysis_prompt: @analysis_prompt
     )
     |> assign(PublicDocuments.page("/paper-pro-daily"))
     |> stream(:papers, [])
     |> show_more()}
  end

  def handle_event("load_more", _params, socket), do: {:noreply, show_more(socket)}

  defp show_more(socket) do
    page = PaperProDaily.list_papers!(page: [offset: socket.assigns.shown, limit: @page_size])

    socket
    |> stream(:papers, Enum.map(page.results, &shown/1))
    |> assign(shown: socket.assigns.shown + length(page.results), more?: page.more?)
  end

  # The picture's address changes whenever the paper is saved again, so a browser
  # may keep each one for good.
  defp shown(paper) do
    paper
    |> Map.take([:date, :title, :arxiv_url, :chatgpt_url, :author, :picture_alt])
    |> Map.merge(Reading.render(paper.answer))
    |> Map.merge(%{
      id: Date.to_iso8601(paper.date),
      picture:
        "/paper-pro-daily/pictures/#{paper.date}?v=#{DateTime.to_unix(paper.updated_at, :microsecond)}",
      markdown: Reading.details_markdown(paper)
    })
  end

  def render(assigns) do
    ~H"""
    <Regent.Structure.frame class="rl-root" id="paper-daily-top" tabindex="-1">
      <RegentsWeb.HomeLive.landing_header blog?={true} />
      <main id="main-content">
        <section class="rg-blog rg-sheet paper-daily" aria-labelledby="paper-daily-title">
          <header class="rg-blog__intro">
            <h1 id="paper-daily-title">Paper Pro Daily</h1>
            <p>A research paper each day, read with ChatGPT Astra 6 Pro.</p>
            <div class="paper-daily__actions">
              <Regent.Primitives.copy_button id="paper-daily-copy-page" text={@page_markdown}>
                Copy Entire Page as Markdown
              </Regent.Primitives.copy_button>
              <Regent.Primitives.button
                id="paper-daily-view-prompt"
                variant="secondary"
                aria-haspopup="dialog"
                aria-controls="paper-daily-prompt-dialog"
                phx-click={JS.dispatch("regents:open", to: "#paper-daily-prompt-dialog")}
              >
                View Prompt to ChatGPT Pro for Paper Analysis
              </Regent.Primitives.button>
            </div>
          </header>

          <ol id="paper-daily-list" class="paper-daily__list" phx-update="stream" role="list">
            <li :for={{dom_id, paper} <- @streams.papers} id={dom_id}>
              <.paper id={dom_id} paper={paper} />
            </li>
          </ol>

          <p
            :if={@more?}
            id="paper-daily-more"
            class="paper-daily__more"
            role="status"
            phx-hook="InfiniteScroll"
            data-event="load_more"
            data-cursor={@shown}
          >
            Loading more papers…
          </p>
          <p :if={@shown == 0} class="paper-daily__more">No papers yet.</p>
          <div :if={!@more? && @shown > 0} class="paper-daily__end">
            <a
              href="#paper-daily-top"
              class="rg-button rg-button--secondary"
              id="paper-daily-return-top"
            >
              Return to top
            </a>
          </div>
        </section>
      </main>
      <dialog
        id="paper-daily-prompt-dialog"
        class="paper-daily__prompt-dialog"
        aria-labelledby="paper-daily-prompt-title"
        phx-hook="InfoDialog"
      >
        <h2 id="paper-daily-prompt-title">Prompt to ChatGPT Pro for Paper Analysis</h2>
        <pre id="paper-daily-analysis-prompt">{@analysis_prompt}</pre>
        <div class="paper-daily__actions">
          <Regent.Primitives.copy_button
            id="paper-daily-copy-prompt"
            target="paper-daily-analysis-prompt"
          >
            Copy prompt
          </Regent.Primitives.copy_button>
          <form method="dialog">
            <Regent.Primitives.button variant="secondary" type="submit">Close</Regent.Primitives.button>
          </form>
        </div>
      </dialog>
    </Regent.Structure.frame>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PaperMath">
      // The same local KaTeX the blog uses; a paper added by scrolling gets its maths too.
      const mathModuleURL = "/assets/regent-blog/katex.mjs"

      export default {
        mounted() {
          const equations = [...this.el.querySelectorAll("[data-math-style]")]
          if (!equations.length) return

          import(mathModuleURL)
            .then(({default: katex}) => {
              for (const equation of equations) {
                try {
                  katex.render(equation.textContent, equation, {
                    displayMode: equation.dataset.mathStyle === "display",
                    output: "mathml", trust: false, throwOnError: true, maxExpand: 1000, maxSize: 20,
                  })
                  equation.dataset.mathReady = "true"
                } catch {
                  equation.dataset.mathReady = "error"
                }
              }
            })
            .catch(() => {
              for (const equation of equations) equation.dataset.mathReady = "error"
            })
        }
      }
    </script>
    """
  end

  attr :id, :string, required: true
  attr :paper, :map, required: true

  defp paper(assigns) do
    ~H"""
    <article class="paper-daily__item" aria-labelledby={"#{@id}-title"}>
      <img
        class="paper-daily__image"
        src={@paper.picture}
        alt={@paper.picture_alt}
        loading="lazy"
        decoding="async"
      />
      <div class="paper-daily__copy">
        <time datetime={Date.to_iso8601(@paper.date)}>{Calendar.strftime(@paper.date, "%B %-d, %Y")}</time>
        <h2 id={"#{@id}-title"}>{@paper.title}</h2>
        <p class="paper-daily__links">
          <a href={@paper.arxiv_url} rel="noopener noreferrer">Paper Link</a>
          <a href={@paper.chatgpt_url} rel="noopener noreferrer">ChatGPT Thread</a>
        </p>
        <Regent.Primitives.copy_button
          id={"#{@id}-copy-details"}
          text={@paper.markdown}
          class="paper-daily__details"
        >
          <span class="paper-daily__copy-label">
            <span class="paper-daily__copy-icon"><RegentsWeb.Components.RegentLinks.source_icon kind={
              :copy
            } /></span>
            Copy Details
          </span>
        </Regent.Primitives.copy_button>
        <p class="paper-daily__author">Analysis by {@paper.author}</p>
        <div
          id={"#{@id}-excerpt"}
          class="rg-blog__prose paper-daily__text"
          phx-hook=".PaperMath"
          phx-update="ignore"
        >
          {markdown_html(@paper.excerpt_html)}
        </div>
        <div
          :if={@paper.more?}
          id={"#{@id}-full"}
          class="rg-blog__prose paper-daily__text"
          tabindex="-1"
          hidden
          phx-hook=".PaperMath"
          phx-update="ignore"
        >
          {markdown_html(@paper.html)}
          <Regent.Primitives.button
            id={"#{@id}-show-less"}
            variant="secondary"
            class="paper-daily__read-more"
            aria-controls={"#{@id}-full"}
            phx-click={show_less(@id)}
          >
            Show less
          </Regent.Primitives.button>
        </div>
        <button
          :if={@paper.more?}
          id={"#{@id}-read-more"}
          type="button"
          class="rg-button rg-button--secondary paper-daily__read-more"
          aria-controls={"#{@id}-full"}
          aria-expanded="false"
          phx-click={read_more(@id)}
        >
          <span class="rg-button__label">Read more</span>
        </button>
      </div>
    </article>
    """
  end

  # The whole answer takes the opening's place, and reading carries on from its start.
  defp read_more(id) do
    JS.set_attribute({"hidden", ""}, to: "##{id}-excerpt")
    |> JS.remove_attribute("hidden", to: "##{id}-full")
    |> JS.set_attribute({"hidden", ""}, to: "##{id}-read-more")
    |> JS.set_attribute({"aria-expanded", "true"}, to: "##{id}-read-more")
    |> JS.focus(to: "##{id}-full")
  end

  defp show_less(id) do
    JS.set_attribute({"hidden", ""}, to: "##{id}-full")
    |> JS.remove_attribute("hidden", to: "##{id}-excerpt")
    |> JS.remove_attribute("hidden", to: "##{id}-read-more")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-read-more")
    |> JS.focus(to: "##{id}-read-more")
  end

  # The HTML is MDEx-rendered with raw HTML switched off, from papers only a release command writes.
  # sobelow_skip ["XSS.Raw"]
  defp markdown_html(html), do: Phoenix.HTML.raw(html)
end
