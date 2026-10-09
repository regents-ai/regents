defmodule RegentsWeb.LiteratureController do
  @moduledoc "Serves the literature chart."

  use RegentsWeb, :controller
  alias RegentsWeb.{Literature, PublicDocuments}

  def show(conn, _params),
    do: render(conn, :show, [books: Literature.books()] ++ PublicDocuments.page("/literature"))
end

defmodule RegentsWeb.LiteratureHTML do
  @moduledoc false

  use RegentsWeb, :html

  def show(assigns) do
    ~H"""
    <Regent.Structure.frame class="rl-root">
      <RegentsWeb.HomeLive.landing_header blog?={true} />
      <main id="main-content" class="lit-page">
        <header class="lit-intro">
          <h1>Hope for people, hope for machines</h1>
          <p>
            {length(@books)} science-fiction books about artificial minds, from 1950 to 2024. Each
            one sits where it answers two questions: how hopeful is it about human lives and
            agency, and how hopeful is it about the artificial minds' own prospects — their
            freedom, continuity, relationships and a meaningful existence?
          </p>
        </header>

        <figure class="lit-chart" data-literature-chart data-mode="covers">
          <div class="lit-toolbar">
            <div class="lit-switch" role="group" aria-label="Show books as">
              <button type="button" data-lit-mode="covers" aria-pressed="true">Covers</button>
              <button type="button" data-lit-mode="titles" aria-pressed="false">Titles</button>
            </div>
          </div>

          <div class="lit-body">
            <p class="lit-axis lit-axis--y" aria-hidden="true">
              <span>Bleak</span><strong>Outlook for AI</strong><span>Hopeful</span>
            </p>
            <div class="lit-ticks lit-ticks--y" aria-hidden="true">
              <span :for={tick <- Enum.reverse(ticks())}>{signed(tick)}</span>
            </div>

            <div class="lit-frame">
              <div class="lit-plot">
                <span class="lit-grid lit-grid--x" aria-hidden="true"></span>
                <span class="lit-grid lit-grid--y" aria-hidden="true"></span>
                <p
                  :for={{corner, label} <- quadrants()}
                  class={["lit-quadrant", "lit-quadrant--#{corner}"]}
                  data-lit-obstacle
                >
                  {label}
                </p>
                <svg class="lit-leaders" aria-hidden="true"></svg>
                <span
                  :for={book <- @books}
                  class="lit-dot"
                  style={anchor(book)}
                  aria-hidden="true"
                ></span>

                <div
                  :for={book <- @books}
                  id={"book-#{book.slug}"}
                  class="lit-book"
                  style={anchor(book)}
                  data-humanity={book.humanity}
                  data-ai={book.ai}
                >
                  <button
                    type="button"
                    class="lit-mark"
                    aria-label={"#{book.title} by #{book.author}"}
                    aria-expanded="false"
                    aria-controls={"book-#{book.slug}-details"}
                  >
                    <img
                      class="lit-cover"
                      src={~p"/images/literature/#{book.slug <> ".webp"}"}
                      alt=""
                      width="180"
                      height="270"
                      loading="lazy"
                      decoding="async"
                    />
                    <span class="lit-label">
                      <span class="lit-label__title">{book.title}</span>
                      <span class="lit-label__meta">{book.author}</span>
                    </span>
                  </button>

                  <div id={"book-#{book.slug}-details"} class="lit-pop" role="group">
                    <div class="lit-pop__card">
                      <p class="lit-pop__title">{book.title}</p>
                      <p class="lit-pop__byline">{book.author} · {book.year}</p>
                      <dl class="lit-pop__scores">
                        <div>
                          <dt>Humanity</dt>
                          <dd>{signed(book.humanity)}</dd>
                        </div>
                        <div>
                          <dt>AI</dt>
                          <dd>{signed(book.ai)}</dd>
                        </div>
                      </dl>
                      <p class="lit-pop__themes">{book.themes}</p>
                      <a
                        class="lit-pop__link"
                        href={book.goodreads}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        See it on Goodreads <span aria-hidden="true">↗</span>
                      </a>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="lit-ticks lit-ticks--x" aria-hidden="true">
              <span :for={tick <- ticks()}>{signed(tick)}</span>
            </div>
            <p class="lit-axis lit-axis--x" aria-hidden="true">
              <span>Bleak</span><strong>Outlook for humanity</strong><span>Hopeful</span>
            </p>
          </div>

          <figcaption class="lit-note">
            Scores run from −10, annihilation or permanent torment, through 0, mixed or unresolved,
            to +10, exceptionally strong prospects for flourishing. They are readings of each
            book's themes, not measurements or claims about what the authors believe, and a point
            or two either way is often debatable. Spoilers throughout. Covers come from Open
            Library, so the edition shown may be later than the first publication.
          </figcaption>
        </figure>
      </main>
    </Regent.Structure.frame>
    """
  end

  defp quadrants,
    do: [
      {"top-left", "Good for AI, bad for humans"},
      {"top-right", "Good for both"},
      {"bottom-left", "Bad for both"},
      {"bottom-right", "Good for humans, bad for AI"}
    ]

  defp ticks, do: [-10, -5, 0, 5, 10]

  defp anchor(book),
    do: "left: #{(book.humanity + 10) * 5}%; top: #{(10 - book.ai) * 5}%;"

  defp signed(0), do: "0"
  defp signed(score) when score > 0, do: "+#{score}"
  defp signed(score), do: "−#{abs(score)}"
end
