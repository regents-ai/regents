defmodule RegentsWeb.Components.AgentMessage do
  @moduledoc """
  The Agent Message button and its dialog: texts a visitor pastes into their
  agent so it leaves a private message for the site's team under a `topic` the
  site names, through the regents CLI or the site's WebMCP tool. regents.sh has
  no hosted MCP server, so there is no MCP text. Each names this site's address
  and the command and tool read when this module compiles from
  `cli/commands.json` and `priv/tool_manifest.json`, so the texts cannot name a
  command that is not there. `texts/1` gives them to any page that tells an
  agent how.

  Below the texts, a signed-in person leaves a message themselves
  (`RegentsWeb.Components.AgentMessage.Form`); a signed-out visitor sees only
  the texts.
  """

  use Phoenix.Component

  alias RegentsWeb.Live.Session
  alias RegentsWeb.PublicDocuments

  commands = Path.expand("../../../../cli/commands.json", __DIR__)
  manifest = Application.app_dir(:regents, "priv/tool_manifest.json")
  @external_resource commands
  @external_resource manifest

  %{"platform" => platform, "commands" => commands} = commands |> File.read!() |> Jason.decode!()
  %{"command" => command} = Enum.find(commands, &(&1["operation_id"] == "leaveMessage"))

  %{"name" => tool} =
    manifest
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("tools")
    |> Enum.find(&(&1["operation_id"] == "leaveMessage"))

  # `messages leave <topic>`, with the topic left for `texts/1` to fill in.
  @command "regents #{platform} " <> String.replace(command, "<topic>", "")
  @tool tool

  @doc """
  The paste-ready texts for leaving a message under `topic`, each with its one-
  or two-word title: the CLI line and the WebMCP tool call, with this site's
  address and names filled in.
  """
  @spec texts(String.t()) :: [%{id: String.t(), title: String.t(), text: String.t()}]
  def texts(topic) do
    site = PublicDocuments.url("")

    fields = [
      body: "<your message>",
      reply_to: "<where to answer you>",
      operation_id: "<a new UUID>"
    ]

    [
      %{
        id: "cli",
        title: "CLI",
        text: """
        Leave a message for the team at #{site} with the regents CLI, signed as you, once I have paired you with my account there:

        echo '#{Jason.encode!(Jason.OrderedObject.new(fields))}' | #{@command}#{topic}

        Keep the same operation_id if you retry. Only the team reads it.\
        """
      },
      %{
        id: "webmcp",
        title: "WebMCP",
        text: """
        Open #{site} with regents browser --site regents, which signs each call with your agent key, and call its WebMCP tool #{@tool} with this input, once I have paired you with my account there:

        #{Jason.encode!(Jason.OrderedObject.new([topic: topic] ++ fields), pretty: true)}

        Keep the same operation_id if you retry. Only the team reads it.\
        """
      }
    ]
  end

  attr :id, :string, required: true
  attr :dialog, :string, required: true, doc: "The id of the `dialog/1` it opens."

  @doc "The Agent Message button, which opens its dialog."
  def button(assigns) do
    ~H"""
    <Regent.Primitives.button
      id={@id}
      variant="secondary"
      arrow={false}
      class="agent-message-button"
      aria-haspopup="dialog"
      aria-controls={@dialog}
      data-agent-message-open
    >
      <Regent.Icons.icon name="bot-message-square" /> Agent Message
    </Regent.Primitives.button>
    """
  end

  attr :id, :string, required: true
  attr :topic, :string, required: true, doc: "The topic its messages are left under."
  attr :conn, Plug.Conn, required: true, doc: "The page's request, for the form's sign-in."

  @doc """
  The dialog: the texts, each with its copy button, and for a signed-in person
  the form that leaves a message, which runs in a live view of its own
  (`RegentsWeb.AgentMessageLive`) that reads the sign-in. Closed with its X,
  Escape or a press beside it (`assets/js/agent_message.ts`).
  """
  def dialog(assigns) do
    assigns = assign(assigns, texts: texts(assigns.topic), form: "#{assigns.id}-person")

    ~H"""
    <Regent.Structure.dialog
      id={@id}
      class="agent-tools agent-message"
      aria-labelledby={"#{@id}-title"}
      data-agent-message
    >
      <header class="agent-tools__head">
        <h2 id={"#{@id}-title"}>Agent Message</h2>
        <button type="button" class="agent-tools__close" aria-label="Close" data-agent-message-close>
          <Regent.Icons.icon name="x" />
        </button>
        <p class="agent-tools__note agent-message__note">
          Paste one into your agent. Only the Regents team reads it.
        </p>
      </header>
      <div class="agent-tools__body">
        <ol class="agent-tools__list">
          <li :for={text <- @texts} class="agent-tools__tool agent-message__text">
            <div class="agent-message__head">
              <h3>{text.title}</h3>
              <Regent.Primitives.copy_button
                id={"#{@id}-copy-#{text.id}"}
                variant="secondary"
                target={"#{@id}-text-#{text.id}"}
              >
                Copy
              </Regent.Primitives.copy_button>
            </div>
            <pre><code id={"#{@id}-text-#{text.id}"}>{text.text}</code></pre>
          </li>
        </ol>
        {Phoenix.Component.live_render(@conn, RegentsWeb.AgentMessageLive,
          id: "#{@id}-live",
          session: @conn |> Session.render_context() |> Map.merge(%{"id" => @form, "topic" => @topic})
        )}
      </div>
    </Regent.Structure.dialog>
    """
  end
end
