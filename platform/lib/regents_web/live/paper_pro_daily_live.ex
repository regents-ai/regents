defmodule RegentsWeb.PaperProDailyLive do
  @moduledoc "One research paper a day with ChatGPT's reading of it, newest first, loading more as the reader scrolls."
  use RegentsWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Regents.PaperProDaily
  alias RegentsWeb.PaperProDaily.Reading
  alias RegentsWeb.{PublicDocuments, RouteCatalog}

  @page_size 6

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(route_spec: RouteCatalog.fetch!(:paper_pro_daily), shown: 0, more?: false)
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
        "/paper-pro-daily/pictures/#{paper.date}?v=#{DateTime.to_unix(paper.updated_at, :microsecond)}"
    })
  end

  def render(assigns) do
    ~H"""
    <Regent.Structure.frame class="rl-root">
      <RegentsWeb.HomeLive.landing_header blog?={true} />
      <main id="main-content">
        <section class="rg-blog rg-sheet paper-daily" aria-labelledby="paper-daily-title">
          <header class="rg-blog__intro">
            <h1 id="paper-daily-title">Paper Pro Daily</h1>
            <p>A research paper each day, read with ChatGPT Astra 6 Pro.</p>
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
        </section>
      </main>
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
        <p class="paper-daily__author">Authored by {@paper.author}</p>
        <p class="paper-daily__links">
          <a href={@paper.arxiv_url} rel="noopener noreferrer">Paper</a>
          <a href={@paper.chatgpt_url} rel="noopener noreferrer">ChatGPT answer</a>
        </p>
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
        </div>
        <button
          :if={@paper.more?}
          id={"#{@id}-read-more"}
          type="button"
          class="rg-button rg-button--secondary paper-daily__read-more"
          aria-controls={"#{@id}-full"}
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
    |> JS.focus(to: "##{id}-full")
  end

  # The HTML is MDEx-rendered with raw HTML switched off, from papers only a release command writes.
  # sobelow_skip ["XSS.Raw"]
  defp markdown_html(html), do: Phoenix.HTML.raw(html)
end
