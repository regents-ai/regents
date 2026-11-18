defmodule RegentsWeb.Components.Tour do
  @moduledoc """
  A guided tour of a page: a ring round one part of the page at a time, the
  rest of the page gently dimmed, and a small card beside the ring that says
  what the part is, with Skip, Back and Next and a dot for each step.

  The tour plays by itself once in a browser, as the page goes live and never
  over an open window. It only points: the dimming takes no presses, so every
  button on the page, every wallet button above all, works while it shows.
  Escape and Skip end it.

  A page passes its own step list. Each step names its part as a CSS selector
  (`target`), with a one-word `title` and one plain sentence (`text`). A step
  whose part is not on the page is left out, and one with no `target` shows
  its card in the middle of the screen. The browser's `Tour` hook
  (`assets/js/hooks/tour.ts`) keeps the list as it was first drawn and
  remembers in the browser alone, under the tour's `name`, that it was seen.
  Nothing about the tour is kept on the server.
  """
  use RegentsWeb, :html

  # The browser remembers each tour that was seen under this prefix and the tour's name.
  @seen_prefix "regent:tour:"

  attr :id, :string, required: true
  attr :name, :string, required: true, doc: "names the tour in the browser's memory"

  attr :steps, :list,
    required: true,
    doc: "maps of `title`, `text` and, for a step that points at a part, `target`"

  def tour(assigns) do
    assigns = assign(assigns, :key, @seen_prefix <> assigns.name)

    ~H"""
    <div id={@id} phx-hook="Tour" phx-update="ignore" data-tour-key={@key} hidden>
      <template data-tour-steps>
        <div
          :for={step <- @steps}
          data-step
          data-target={step[:target]}
          data-title={step.title}
          data-text={step.text}
        >
        </div>
      </template>
      <template data-tour-layer>
        <div class="tour">
          <p class="visually-hidden" role="status" data-tour-say></p>
          <div class="tour__stage" data-tour-stage hidden>
            <div class="tour__shade" aria-hidden="true">
              <span :for={_ <- 1..4} class="tour__piece"></span>
            </div>
            <canvas class="tour__light" data-tour-canvas aria-hidden="true"></canvas>
            <div class="tour__edge" aria-hidden="true">
              <span :for={_ <- 1..4} class="tour__piece"></span>
            </div>
            <div class="tour__spot">
              <section
                class="tour__card"
                role="dialog"
                aria-labelledby={"#{@id}-title"}
                aria-describedby={"#{@id}-text"}
              >
                <ol class="tour__dots" aria-hidden="true"></ol>
                <div class="tour__words">
                  <h2 id={"#{@id}-title"} class="tour__title" data-tour-title></h2>
                  <p id={"#{@id}-text"} class="tour__text" data-tour-text></p>
                </div>
                <div class="tour__actions">
                  <Regent.Primitives.button variant="quiet" arrow={false} data-tour-skip>
                    Skip
                  </Regent.Primitives.button>
                  <Regent.Primitives.button variant="secondary" arrow={false} data-tour-back>
                    Back
                  </Regent.Primitives.button>
                  <Regent.Primitives.button arrow={false} data-tour-next>
                    Next
                  </Regent.Primitives.button>
                </div>
              </section>
            </div>
          </div>
        </div>
      </template>
    </div>
    """
  end
end
