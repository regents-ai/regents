defmodule RegentsWeb.Components.WorldCube do
  @moduledoc """
  A turning cube whose six faces are windows onto six rooms, one for each world
  it links to.

  The server renders the worlds as a plain list of cards, and that list is the
  whole picture wherever the cube cannot be drawn: no WebGPU, no JavaScript, or
  a visitor who asked for less motion. Where it can, the `WorldCube` hook draws
  the cube on the stage, and the card of the room the visitor has stepped into
  is shown over it with the leave button.

  Each world is a map with `:face` (0 to 5, the cube face its room sits behind,
  fixed by the renderer: 0 a launch bay, 1 a glowing tree, 2 a switchboard, 3 a
  signal observatory, 4 the crown hall, 5 a night harbour), `:name`, `:line` and
  `:href`.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :worlds, :list, required: true

  def cube(assigns) do
    ~H"""
    <section
      id={@id}
      class="world-cube"
      aria-label={@label}
      phx-hook="WorldCube"
      phx-mounted={JS.ignore_attributes(["data-world-ready", "data-world-state", "data-world-face"])}
    >
      <div id={"#{@id}-stage"} class="world-cube__stage" phx-update="ignore" aria-hidden="true">
        <canvas class="world-cube__canvas" data-world-canvas></canvas>
      </div>
      <p class="world-cube__hint">Drag to turn. Click a side to enter.</p>
      <ol class="world-cube__worlds">
        <li :for={world <- @worlds} class="world-cube__world" data-world={world.face}>
          <h3>{world.name}</h3>
          <p>{world.line}</p>
          <a href={world.href} class="rg-button" target="_blank" rel="noopener noreferrer">
            <span class="rg-button__label">
              Visit
              <span class="world-cube__visit-name">{world.name}</span><span class="visually-hidden">, opens in a new tab</span>
            </span>
          </a>
        </li>
      </ol>
      <button type="button" class="world-cube__leave" data-world-leave aria-label="Leave this room">
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <path d="M3 3l10 10M13 3L3 13" fill="none" stroke="currentColor" stroke-width="1.5" />
        </svg>
      </button>
    </section>
    """
  end
end
