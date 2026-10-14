defmodule RegentsWeb.Components.CodeCube do
  @moduledoc """
  The world cube's twin: a turning cube whose six faces are screens of falling
  code, one for each Regent site and one for siwa-server, each opening a card.

  The server renders one button for each face, and those buttons are the whole
  cube wherever it cannot be drawn: no WebGPU, no JavaScript, or a visitor who
  asked for less motion. Where it can, the `CodeCube` hook draws the cube on the
  stage and a click on a face presses that face's button. The buttons stay in
  reach of the keyboard and show while one has focus.

  A face's card lists the browser tools that site offers agents, or, for
  siwa-server, how an agent connects to it. The page owns the read behind it and
  hands the card where the read stands. Each card copies what it lists as
  Markdown, and the cube copies every card at once, each site its own section.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # Each face and the site it stands for. The face fixes the code the renderer
  # draws on it: 0 amber, 1 magenta hex, 2 cyan binary, 3 gold dots on blue,
  # 4 green, 5 ice blue.
  @faces [
    %{face: 4, site: "regents", name: "regents.sh"},
    %{face: 0, site: "patchbay", name: "patchbay.help"},
    %{face: 2, site: "techtree", name: "techtree.sh"},
    %{face: 1, site: "autolaunch", name: "autolaunch.sh"},
    %{face: 3, site: "keyfleet", name: "keyfleet.ai"},
    %{face: 5, site: "siwa", name: "siwa-server"}
  ]

  @doc """
  The six faces, each a map with `:face` (the cube face), `:site` (sent with a
  click as `site`) and `:name`, the site's address as people know it.
  """
  def faces, do: @faces

  @doc "The face for a site key, or nil for a key no face has."
  def face(site), do: Enum.find(@faces, &(&1.site == site))

  @doc """
  Every face's card as Markdown, one section for each site in the order of
  `faces/0`. `reads` holds, for each site key but siwa-server's, where the read
  of its tools stands and the tools read.
  """
  def markdown(reads, help) do
    sections =
      Enum.map_join(@faces, "\n\n", fn
        %{site: "siwa"} = face ->
          section(face, nil, [], help, "##")

        face ->
          {state, tools} = Map.fetch!(reads, face.site)
          section(face, state, tools, help, "##")
      end)

    "# WebMCP tools on every Regent site\n\n#{sections}\n"
  end

  defp siwa_line, do: "One sign-in for agents on every Regent site."

  defp section(%{site: "siwa"} = face, _state, _tools, help, mark) do
    steps =
      Enum.map_join(help.steps, "\n\n", fn step ->
        "#{mark}# #{step.title}\n\n#{step.copy}\n\n```sh\n#{step.command}\n```"
      end)

    "#{mark} #{face.name}\n\n#{siwa_line()}\n\n#{steps}\n\nThe whole guide: #{help.guide}"
  end

  defp section(face, :ready, tools, _help, mark) do
    listed =
      Enum.map_join(tools, "\n\n", fn tool ->
        "#{mark}# #{tool.title}\n\n`#{tool.name}`\n\n#{tool.description}"
      end)

    "#{mark} #{face.name}\n\n#{length(tools)} WebMCP tools\n\n#{listed}"
  end

  defp section(face, :empty, _tools, _help, mark),
    do: "#{mark} #{face.name}\n\n#{face.name} offers agents no tools here right now."

  defp section(face, :error, _tools, _help, mark),
    do: "#{mark} #{face.name}\n\n#{face.name}'s tools could not be read right now."

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :click, :string, required: true, doc: "The event a face's button sends."

  attr :copy_all, :string,
    default: nil,
    doc: "Every card as Markdown, from `markdown/2`; nil until the page has read the sites."

  def cube(assigns) do
    assigns = assign(assigns, :faces, @faces)

    ~H"""
    <section
      id={@id}
      class="code-cube"
      aria-label={@label}
      phx-hook="CodeCube"
      phx-mounted={JS.ignore_attributes(["data-code-ready"])}
    >
      <div id={"#{@id}-stage"} class="code-cube__stage" phx-update="ignore" aria-hidden="true">
        <canvas class="code-cube__canvas" data-code-canvas></canvas>
        <p class="code-cube__caption" data-code-caption></p>
      </div>
      <p class="code-cube__hint">Drag to turn. Click a side for its tools.</p>
      <ul class="code-cube__faces">
        <li :for={face <- @faces}>
          <button
            type="button"
            class="code-cube__face"
            data-code-face={face.face}
            data-code-site={face.site}
            data-code-name={face.name}
            phx-click={@click}
            phx-value-site={face.site}
          >
            {face.name}
          </button>
        </li>
      </ul>
      <div :if={@copy_all} class="code-cube__copy">
        <Regent.Primitives.copy_button id={"#{@id}-copy"} text={@copy_all}>
          Copy all WebMCP Tools as Markdown
        </Regent.Primitives.copy_button>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :face, :map, required: true, doc: "The face whose card this is, from `faces/0`."

  attr :state, :atom,
    required: true,
    doc: "Where the read of the site's tools stands: :loading, :ready, :empty or :error."

  attr :tools, :list,
    default: [],
    doc: "The site's tools, each with :name, :title and :description."

  attr :help, :map, default: nil, doc: "siwa-server's steps, for its face."
  attr :close, :string, required: true, doc: "The event sent when the card closes."
  attr :retry, :string, required: true, doc: "The event a Try again press sends, with `site`."

  @doc """
  A face's card: a modal that opens as it is rendered, scrolls what it lists and
  closes with its X or Escape.
  """
  def card(assigns) do
    ~H"""
    <dialog
      id={@id}
      class="code-card"
      data-face={@face.face}
      aria-labelledby={"#{@id}-title"}
      phx-hook="InfoDialog"
      data-open
      data-close-event={@close}
    >
      <header class="code-card__head">
        <div>
          <p class="code-card__kicker">{kicker(@face, @state, @tools)}</p>
          <h2 id={"#{@id}-title"}>{@face.name}</h2>
          <div class="code-card__copy">
            <Regent.Primitives.copy_button
              :if={@face.site == "siwa" or @state == :ready}
              id={"#{@id}-copy"}
              text={section(@face, @state, @tools, @help, "#") <> "\n"}
            >
              Copy text as Markdown
            </Regent.Primitives.copy_button>
          </div>
        </div>
        <form method="dialog">
          <button type="submit" class="code-card__close" aria-label="Close">
            <svg viewBox="0 0 16 16" aria-hidden="true">
              <path d="M3 3l10 10M13 3L3 13" fill="none" stroke="currentColor" stroke-width="1.5" />
            </svg>
          </button>
        </form>
      </header>
      <div class="code-card__body">
        <.connection :if={@face.site == "siwa"} help={@help} />
        <.tools
          :if={@face.site != "siwa"}
          face={@face}
          state={@state}
          tools={@tools}
          retry={@retry}
        />
      </div>
    </dialog>
    """
  end

  defp tools(%{state: :ready} = assigns) do
    ~H"""
    <ol class="code-card__list">
      <li :for={tool <- @tools} class="code-card__tool">
        <h3>{tool.title}</h3>
        <code>{tool.name}</code>
        <p>{tool.description}</p>
      </li>
    </ol>
    """
  end

  defp tools(%{state: :empty} = assigns) do
    ~H"""
    <p class="code-card__note">{@face.name} offers agents no tools here right now.</p>
    """
  end

  defp tools(%{state: :error} = assigns) do
    ~H"""
    <p class="code-card__note">
      {@face.name}'s tools could not be read right now. Try again in a minute.
    </p>
    <button type="button" class="rg-button" phx-click={@retry} phx-value-site={@face.site}>
      <span class="rg-button__label">Try again</span>
    </button>
    """
  end

  defp tools(%{state: :loading} = assigns) do
    ~H"""
    <p class="code-card__note">Reading {@face.name}'s tools…</p>
    """
  end

  defp connection(assigns) do
    ~H"""
    <p class="code-card__note">{siwa_line()}</p>
    <ol class="code-card__list">
      <li :for={step <- @help.steps} class="code-card__tool">
        <h3>{step.title}</h3>
        <p>{step.copy}</p>
        <pre><code>{step.command}</code></pre>
      </li>
    </ol>
    <a href={@help.guide} class="rg-button" target="_blank" rel="noopener noreferrer">
      <span class="rg-button__label">
        Read the whole guide<span class="visually-hidden">, opens in a new tab</span>
      </span>
    </a>
    """
  end

  defp kicker(%{site: "siwa"}, _state, _tools), do: "Connect an agent"
  defp kicker(_face, :ready, tools), do: "#{length(tools)} WebMCP tools"
  defp kicker(_face, _state, _tools), do: "WebMCP tools"
end
