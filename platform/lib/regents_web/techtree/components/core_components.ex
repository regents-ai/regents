defmodule RegentsWeb.Techtree.CoreComponents do
  @moduledoc """
  The small set of pieces every page is built from.

  Each one is presentation only: it decides how something reads, never what is
  true. Values arrive already resolved from the imported catalog, and every one
  of them is escaped as text — nothing on this site renders markup that came
  from a document.

  Commands are the one place that needs care. An installation or run
  instruction is always held as a list of arguments, because that is the only
  form a machine should ever be handed. Turning it into a single line is a
  courtesy for a human reader, done here, at the last moment, and never used as
  the thing that runs.
  """

  use Phoenix.Component

  @doc """
  Show one command, built from the arguments that make it up.

  The copy control hands over exactly the characters shown, and nothing on this
  site ever runs them: what a reader copies is what the release published, and
  where it is run is their business.
  """
  attr :argv, :list, default: nil

  attr :lines, :list,
    default: nil,
    doc: "ordered {:command, argv} and {:comment, text} lines for one copyable shell block"

  attr :label, :string, default: nil
  attr :copy, :boolean, default: true
  attr :id, :string, default: nil

  def command_block(assigns) do
    command = command_text(assigns)

    assigns =
      assigns
      |> assign(:command, command)
      |> assign(:copy_id, assigns.id || command_id(command, assigns.label))

    ~H"""
    <Regent.Structure.panel class="command rg-support-panel">
      <div class="command__head">
        <p class="command__label">{@label || "Command"}</p>
        <Regent.Primitives.copy_button
          :if={@copy}
          id={@copy_id}
          target={"#{@copy_id}-text"}
          class="command__copy"
        >
          Copy
        </Regent.Primitives.copy_button>
      </div>
      <pre
        id={"#{@copy_id}-text"}
        class="command__block"
        tabindex="0"
        role="region"
        aria-label="Command"
      ><code>{@command}</code></pre>
    </Regent.Structure.panel>
    """
  end

  @doc """
  Show one line of instruction meant for an agent rather than a shell.

  It carries the same copy control a command does, because a reader hands it
  over the same way. It is drawn differently on purpose: no prompt character in
  front of it, prose rather than mono, and it wraps instead of running off the
  side, because it is a sentence and a reader has to be able to read all of it.
  """
  attr :text, :string, required: true
  attr :label, :string, required: true
  attr :id, :string, required: true
  attr :copy_variant, :string, default: "secondary"

  def prompt_block(assigns) do
    ~H"""
    <Regent.Structure.panel class="command command--prose rg-support-panel">
      <div class="command__head">
        <p class="command__label">{@label}</p>
        <Regent.Primitives.copy_button
          id={@id}
          target={"#{@id}-text"}
          variant={@copy_variant}
          class="command__copy"
        >
          Copy
        </Regent.Primitives.copy_button>
      </div>
      <p id={"#{@id}-text"} class="command__block">{@text}</p>
    </Regent.Structure.panel>
    """
  end

  @doc """
  What a machine needs before a Climb can run on it, from the release's
  published minimums, with any needs particular to one page added after them.
  """
  attr :minimums, :map, required: true
  attr :provider, :boolean, required: true
  attr :hermes, :boolean, required: true
  slot :inner_block

  def requirements(assigns) do
    ~H"""
    <ul class="needs">
      <li>macOS or Linux</li>
      <li :if={@minimums["uv"]}>uv {@minimums["uv"]} or later</li>
      <li :if={@minimums["python"]}>Python {@minimums["python"]}, installed for you by uv</li>
      <li :if={@minimums["docker_required"]}>Docker, running</li>
      <li :if={@hermes && @minimums["hermes_version"]}>
        Hermes {@minimums["hermes_version"]} or later
      </li>
      <li :if={@provider}>An account with a model provider you choose; its calls may cost money</li>
      {render_slot(@inner_block)}
    </ul>
    """
  end

  @doc """
  A list of short facts, one per row.
  """
  slot :fact do
    attr :term, :string, required: true
  end

  def definition_list(assigns) do
    ~H"""
    <dl class="facts">
      <%= for fact <- @fact do %>
        <dt class="facts__term">{fact.term}</dt>
        <dd class="facts__value">{render_slot(fact)}</dd>
      <% end %>
    </dl>
    """
  end

  # Display only. An argument that would need quoting in a shell is shown
  # quoted, so that what a reader copies is what the argument list means.
  defp display_command(argv), do: Enum.map_join(argv, " ", &quote_argument/1)

  defp command_text(%{argv: argv, lines: nil}) when is_list(argv),
    do: display_command(argv)

  defp command_text(%{argv: nil, lines: lines}) when is_list(lines) do
    Enum.map_join(lines, "\n", fn
      {:command, argv} when is_list(argv) -> display_command(argv)
      {:comment, text} when is_binary(text) -> "# " <> text
    end)
  end

  defp command_text(_assigns) do
    raise ArgumentError, "command_block requires exactly one of :argv or :lines"
  end

  # A stable name for the copy control, derived from what it copies, so that a
  # page holding several commands does not have to name each one by hand.
  defp command_id(command, label) do
    digest = :crypto.hash(:sha256, [label || "", command]) |> Base.encode16(case: :lower)
    "copy-command-" <> String.slice(digest, 0, 12)
  end

  defp quote_argument(argument) do
    if String.match?(argument, ~r|\A[A-Za-z0-9_@%+=:,./-]+\z|) do
      argument
    else
      "'" <> String.replace(argument, "'", "'\\''") <> "'"
    end
  end
end
