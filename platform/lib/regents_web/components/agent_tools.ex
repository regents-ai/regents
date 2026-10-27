defmodule RegentsWeb.Components.AgentTools do
  @moduledoc """
  The WebMCP tools every page offers an agent, read when this module compiles
  from `priv/tool_manifest.json`, the file the pages register them from
  (`assets/js/public_tools.ts`). The button says how many there are and opens a
  dialog listing each tool with its description, which copies the list as
  Markdown, or every Regent site's tools at once.
  """

  use Phoenix.Component

  manifest = Application.app_dir(:regents, "priv/tool_manifest.json")
  @external_resource manifest

  @tools (for tool <- manifest |> File.read!() |> Jason.decode!() |> Map.fetch!("tools") do
            %{name: tool["name"], title: tool["title"], description: tool["description"]}
          end)

  @count "#{length(@tools)} WebMCP Tools"
  @label "Agents see #{@count}"

  @markdown """
  # Regents Labs: #{@label}

  #{Enum.map_join(@tools, "\n\n", &"## #{&1.title}\n\n`#{&1.name}`\n\n#{&1.description}")}
  """

  attr :id, :string, required: true
  attr :dialog, :string, required: true, doc: "The id of the `dialog/1` it opens."
  attr :class, :string, default: nil, doc: "Classes for a button given its own words."
  slot :inner_block, doc: "Its own words, in place of the count."

  @doc """
  The button naming how many tools agents see, which opens their list. A phone
  shows only the count. Given its own words, it shows those instead.
  """
  def button(%{inner_block: [_ | _]} = assigns) do
    ~H"""
    <button
      id={@id}
      class={@class}
      type="button"
      aria-haspopup="dialog"
      aria-controls={@dialog}
      data-agent-tools-open
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  def button(assigns) do
    assigns = assign(assigns, label: @label, count: @count)

    ~H"""
    <button
      id={@id}
      class="agent-tools-button"
      type="button"
      aria-haspopup="dialog"
      aria-controls={@dialog}
      aria-label={@label}
      data-agent-tools-open
    >
      <span class="agent-tools-button__lead">Agents see</span> {@count}
    </button>
    """
  end

  attr :id, :string, required: true

  @doc """
  The dialog listing every tool, closed with its X, Escape or a press beside it.
  Besides the copy of its own list, it copies every Regent site's tools at once,
  which the page reads each time the dialog opens until one read succeeds
  (`assets/js/agent_tools.ts`); until then that button waits, and the line
  under it says how the read stands. Everything in it is fixed when the page is
  built, so the page never redraws it: an opening, and what the read put in it,
  last through the page connecting and every later update.
  """
  def dialog(assigns) do
    assigns = assign(assigns, label: @label, tools: @tools, markdown: @markdown)

    ~H"""
    <dialog
      id={@id}
      class="agent-tools"
      aria-labelledby={"#{@id}-title"}
      data-agent-tools
      phx-update="ignore"
    >
      <header class="agent-tools__head">
        <h2 id={"#{@id}-title"}>{@label}</h2>
        <button type="button" class="agent-tools__close" aria-label="Close" data-agent-tools-close>
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M3 3l10 10M13 3L3 13" fill="none" stroke="currentColor" stroke-width="1.5" />
          </svg>
        </button>
        <div class="agent-tools__copies">
          <Regent.Primitives.copy_button id={"#{@id}-copy"} text={@markdown}>
            Copy as Markdown
          </Regent.Primitives.copy_button>
          <div class="agent-tools__every-site">
            <Regent.Primitives.copy_button
              id={"#{@id}-copy-all"}
              target={"#{@id}-all"}
              data-agent-tools-copy-all
              {%{"disabled" => true}}
            >
              Copy all Regents WebMCP tools
            </Regent.Primitives.copy_button>
            <p class="agent-tools__note" data-agent-tools-note>Reading every site's tools…</p>
            <pre id={"#{@id}-all"} hidden data-agent-tools-all></pre>
          </div>
        </div>
      </header>
      <div class="agent-tools__body">
        <ol class="agent-tools__list">
          <li :for={tool <- @tools} class="agent-tools__tool">
            <h3>{tool.title}</h3>
            <code>{tool.name}</code>
            <p>{tool.description}</p>
          </li>
        </ol>
      </div>
    </dialog>
    """
  end
end
