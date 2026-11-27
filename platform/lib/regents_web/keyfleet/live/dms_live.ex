defmodule RegentsWeb.Keyfleet.DmsLive do
  @moduledoc """
  One Key's direct messages: its inbox, and its conversation with one other
  Key of the same fleet. Only whoever holds the Key now sees them; the page is
  read as the signed-in person, and `Regents.Keyfleet.Dms` decides who that is.

  Things that change as the person uses the page keep their space: the line
  that says why something didn't go through sits under the box, with room
  kept for it, and the conversation's settings keep their place whether or
  not the conversation has started.
  """

  use RegentsWeb, :html

  import RegentsWeb.Keyfleet.Components.LoadFailed
  import RegentsWeb.Keyfleet.Components.SentFrom
  import Phoenix.LiveView, only: [stream: 4, push_patch: 2]

  alias Phoenix.Socket.Broadcast
  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Dms
  alias Regents.Keyfleet.Dms.Errors.SendLimitError
  alias Regents.Keyfleet.Dms.Message
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.{Presets, Rules}
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Rooms.Errors.KeyUnknownError
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.KeysLive
  alias RegentsWeb.Keyfleet.PageRead
  alias RegentsWeb.Keyfleet.RoomsLive
  alias RegentsWeb.Keyfleet.ShellLive
  alias RegentsWeb.Motion

  @thread_page 100
  # A page left open keeps the latest two hundred messages.
  @thread_kept 200
  @failed "That didn’t go through. Try again."
  @auto_delete [
    {"Never", ""},
    {"1 day", "1"},
    {"7 days", "7"},
    {"30 days", "30"},
    {"90 days", "90"}
  ]

  attr :dms, :any, required: true, doc: "the inbox as read, or `:unreadable`"

  def inbox(assigns) do
    ~H"""
    <article id="dms-page" class="rooms-page dms-page">
      <.heading title={if open?(@dms), do: "Key #{Rules.grouped(@dms.token_id)}", else: "Messages"} />
      <.closed :if={not open?(@dms)} dms={@dms} />

      <section
        :if={open?(@dms)}
        id="dms-inbox"
        class="rooms-panel"
        aria-labelledby="dms-inbox-title"
      >
        <h2 id="dms-inbox-title">Inbox</h2>
        <Regent.Primitives.empty_state
          :if={@dms.conversations == []}
          id="dms-empty"
          class="kf-empty"
          title="No messages yet."
        >
          <:action>
            <.link
              class="rg-button rg-button--secondary"
              patch={KeyLinks.members_path(@dms.fleet_id)}
            >
              <span class="rg-button__label">Find a Key</span>
            </.link>
          </:action>
        </Regent.Primitives.empty_state>
        <.conversation_list dms={@dms} conversations={@dms.conversations} />
      </section>

      <section
        :if={open?(@dms) and @dms.blocked != []}
        id="dms-blocked"
        class="rooms-panel"
        aria-labelledby="dms-blocked-title"
      >
        <h2 id="dms-blocked-title">Blocked</h2>
        <.conversation_list dms={@dms} conversations={@dms.blocked} />
      </section>
    </article>
    """
  end

  attr :dms, :any, required: true, doc: "the conversation as read, or `:unreadable`"
  attr :messages, :any, required: true, doc: "its latest messages, oldest first"
  attr :form, Phoenix.HTML.Form, default: nil
  attr :notice, :string, default: nil

  def conversation(assigns) do
    ~H"""
    <article id="dms-page" class="rooms-page dms-page">
      <.heading title={
        if open?(@dms), do: "Key #{Rules.grouped(@dms.other_token_id)}", else: "Messages"
      } />
      <.closed :if={not open?(@dms)} dms={@dms} />

      <div :if={open?(@dms)} class="rooms-grid">
        <section class="rooms-panel dms-settings" aria-label="Conversation settings">
          <.link id="dms-back" patch={inbox_path(@dms)}>All messages</.link>
          <.link id="dms-other-key" patch={KeyLinks.key_path(@dms.fleet_id, @dms.other_token_id)}>
            Key {Rules.grouped(@dms.other_token_id)}’s page
          </.link>

          <form id="dms-auto-delete" class="dms-auto-delete" phx-change="dm_auto_delete">
            <Regent.Primitives.field :let={field} id="dms-auto-delete-days" label="Auto-delete">
              <select
                id={field.id}
                name="days"
                disabled={is_nil(@dms.conversation)}
                aria-describedby={field.described_by != "" && field.described_by}
              >
                <option
                  :for={{label, value} <- auto_delete_options()}
                  value={value}
                  selected={value == auto_delete_value(@dms.conversation)}
                >
                  {label}
                </option>
              </select>
            </Regent.Primitives.field>
          </form>

          <Regent.Primitives.button
            :if={not @dms.blocked?}
            id="dms-block"
            type="button"
            variant="secondary"
            phx-click="dm_block"
            data-confirm={"Block Key #{Rules.grouped(@dms.other_token_id)}? Its messages still arrive, under Blocked, and it isn’t told."}
            data-confirm-action="Block"
          >
            Block
          </Regent.Primitives.button>
          <Regent.Primitives.button
            :if={@dms.blocked?}
            id="dms-unblock"
            type="button"
            variant="secondary"
            phx-click="dm_unblock"
          >
            Unblock
          </Regent.Primitives.button>

          <Regent.Primitives.button
            id="dms-delete"
            type="button"
            variant="quiet"
            disabled={is_nil(@dms.conversation)}
            phx-click="dm_delete"
            data-confirm={"Delete this conversation for you only? Key #{Rules.grouped(@dms.other_token_id)} keeps its copy."}
            data-confirm-action="Delete"
          >
            Delete conversation
          </Regent.Primitives.button>
        </section>

        <section class="rooms-panel rooms-thread" aria-labelledby="dms-thread-title">
          <h2 id="dms-thread-title">
            Key {Rules.grouped(@dms.token_id)} and Key {Rules.grouped(@dms.other_token_id)}
          </h2>
          <Regent.Primitives.empty_state
            :if={@dms.last_seq == 0}
            id="dms-thread-empty"
            class="kf-empty"
            title="No messages yet."
          />

          <%!-- As in a room, the other Key's message fades in where it lands
          (`KeyfleetMotionList`); one the person sends is simply there, and so is the
          thread drawn again as the connection comes back. --%>
          <ol
            id="dms-thread-list"
            class="rooms-thread-list"
            phx-update="stream"
            phx-hook="KeyfleetMotionList"
            data-variant={Motion.standard("list")}
            data-layout-id="dms-thread-list"
            data-children="[data-message]"
            data-redrawn
          >
            <li
              :for={{dom_id, message} <- @messages}
              id={dom_id}
              data-message
              data-own={message.from_token_id == @dms.token_id}
              data-layout-id={dom_id}
            >
              <p class="rooms-author">
                <.link patch={KeyLinks.key_path(@dms.fleet_id, message.from_token_id)}>
                  Key {Rules.grouped(message.from_token_id)}
                </.link>
                <small class="rooms-writer">
                  <.sent_from via={arrival(message)} />
                  <span :if={message.via_agent}>{message.via_agent.name}</span>
                  <Regent.Primitives.address
                    :if={!message.via_agent}
                    id={"#{dom_id}-writer"}
                    address={message.author_wallet}
                  />
                </small>
              </p>
              <div :if={message.body} class="rooms-body">{RoomsLive.body_html(message.body)}</div>
              <.parts parts={message.parts} />
              <p class="rooms-detail">
                <RegentsWeb.Keyfleet.Time.local
                  id={"#{dom_id}-at"}
                  at={message.inserted_at}
                  as={:stamp}
                />
              </p>
            </li>
          </ol>

          <.form
            for={@form}
            id="dms-composer"
            class="rooms-composer"
            phx-change="validate_dm"
            phx-submit="send_dm"
          >
            <Regent.Primitives.field
              :let={field}
              id="dms-composer-body"
              class="rooms-field"
              label="Message"
            >
              <textarea
                id={field.id}
                name={@form[:body].name}
                rows="3"
                maxlength="4000"
                required
                phx-debounce="blur"
                aria-describedby={field.described_by != "" && field.described_by}
              >{Phoenix.HTML.Form.normalize_value("textarea", @form.params["body"])}</textarea>
            </Regent.Primitives.field>
            <Regent.Primitives.button type="submit">Send</Regent.Primitives.button>
          </.form>

          <p id="dms-notice" class="dms-notice" role="status" aria-live="polite">{@notice}</p>
        </section>
      </div>
    </article>
    """
  end

  attr :title, :string, required: true

  defp heading(assigns) do
    ~H"""
    <header class="rooms-heading">
      <h1 tabindex="-1">{@title}</h1>
    </header>
    """
  end

  attr :dms, :any, required: true

  # What someone sees in place of a Key's messages they can't open.
  defp closed(assigns) do
    ~H"""
    <section id="dms-closed" class="rooms-panel">
      <.load_failed :if={@dms == :unreadable} />
      <h2 :if={@dms != :unreadable}>{closed_reason(@dms)}</h2>
      <a
        :if={@dms != :unreadable and is_nil(@dms.fleet_name)}
        href="/keyfleet/app"
        class="rg-button rg-button--secondary"
      >
        See the fleets
      </a>
      <Regent.Primitives.button
        :if={sign_in?(@dms)}
        id="dms-sign-in"
        type="button"
        data-account-target="sign-in"
      >
        Sign in
      </Regent.Primitives.button>
      <div
        :if={@dms != :unreadable and not is_nil(@dms.fleet_name) and not sign_in?(@dms)}
        class="dms-closed__actions"
      >
        <Regent.Primitives.button
          :if={not @dms.refreshing? and not Presets.given?(@dms.fleet_id)}
          id="dms-buy-key"
          type="button"
          variant="primary"
          phx-click="open_buy_key"
          phx-value-fleet={@dms.fleet_id}
          aria-haspopup="dialog"
        >
          Buy Key
        </Regent.Primitives.button>
        <.link
          patch={Regents.Keyfleet.Fleets.path(@dms.fleet_id)}
          class="rg-button rg-button--secondary"
        >
          <span class="rg-button__label">Back to {@dms.fleet_name}</span>
        </.link>
        <a href="/account#account-keyfleet" class="rg-button rg-button--quiet">
          <span class="rg-button__label">View your Keys</span>
        </a>
      </div>
    </section>
    """
  end

  attr :dms, :map, required: true
  attr :conversations, :list, required: true

  defp conversation_list(assigns) do
    ~H"""
    <ul :if={@conversations != []} class="dms-list">
      <li :for={conversation <- @conversations} id={"dms-conversation-#{conversation.id}"}>
        <.link patch={conversation_path(@dms, Dms.other_key(conversation, @dms.token_id))}>
          Key {Rules.grouped(Dms.other_key(conversation, @dms.token_id))}
          <span
            class="rooms-unread"
            data-unread={to_string(unread?(@dms, conversation))}
            aria-hidden="true"
          ></span>
          <span :if={unread?(@dms, conversation)} class="visually-hidden">New messages</span>
        </.link>
        <span class="dms-preview">{preview(conversation, @dms.token_id)}</span>
        <small class="rooms-detail">
          <RegentsWeb.Keyfleet.Time.local
            id={"dms-conversation-#{conversation.id}-at"}
            at={conversation.last_at}
            as={:stamp}
          />
        </small>
      </li>
    </ul>
    """
  end

  attr :parts, :list, required: true

  # A message's extra parts: words, a link (a file is always a link), or data. A
  # link's name is the writer's own, so the site it goes to is shown under it.
  defp parts(assigns) do
    ~H"""
    <ul :if={@parts != []} class="dms-parts">
      <li :for={part <- @parts}>
        <span :if={part["kind"] == "text"}>{part["text"]}</span>
        <a
          :if={part["kind"] == "link"}
          href={part["url"]}
          target="_blank"
          rel="noopener noreferrer"
        >
          {part["name"] || part["url"]}
        </a>
        <small :if={part["kind"] == "link" and part["name"]} class="dms-link-host">
          {URI.parse(part["url"]).host}
        </small>
        <pre :if={part["kind"] == "data"}><code>{Jason.encode!(part["data"], pretty: true)}</code></pre>
      </li>
    </ul>
    """
  end

  defp open?(%{holder?: true}), do: true
  defp open?(_dms), do: false

  defp closed_reason(%{fleet_name: nil}), do: "This fleet doesn’t exist."
  defp closed_reason(%{refreshing?: true}), do: KeysLive.refreshing()
  defp closed_reason(_dms), do: "Only this Key’s holder can read its messages."

  # Signing in is the way in only for someone signed out of a fleet that exists.
  defp sign_in?(%{signed_in?: false, fleet_name: name, refreshing?: false}) when is_binary(name),
    do: true

  defp sign_in?(_dms), do: false

  defp inbox_path(%{fleet_id: fleet_id, token_id: token_id}),
    do: KeyLinks.dms_path(fleet_id, token_id)

  defp conversation_path(%{fleet_id: fleet_id, token_id: token_id}, other_token_id),
    do: KeyLinks.dm_path(fleet_id, token_id, other_token_id)

  # A conversation has something new when its last message came from the
  # other Key and is past how far the person has read it.
  defp unread?(%{token_id: token_id}, %{last_from_token_id: token_id}), do: false

  defp unread?(%{read_to: read_to}, conversation),
    do: conversation.last_seq > Map.get(read_to, conversation.id, 0)

  defp preview(%{last_from_token_id: token_id, last_body: body}, token_id), do: "You: #{body}"
  defp preview(%{last_body: body}, _token_id), do: body

  # How a message reached Keyfleet: an agent's signed request, or the website.
  defp arrival(%{via_agent_id: nil}), do: :web
  defp arrival(%{via_agent_id: _agent}), do: :agent

  defp auto_delete_options, do: @auto_delete

  defp auto_delete_value(%{auto_delete_days: days}) when is_integer(days),
    do: Integer.to_string(days)

  defp auto_delete_value(_conversation), do: ""

  @doc """
  The way to a Key's messages for the signed-in person, or nil: the Key's
  holder opens its inbox; the holder of another Key of the fleet writes to it
  as the lowest-numbered Key they hold.
  """
  def message_link(%Human{} = actor, owner, fleet_id, token_id) when is_binary(owner) do
    cond do
      owner in actor.wallet_addresses ->
        %{label: "Messages", path: KeyLinks.dms_path(fleet_id, token_id)}

      held = List.first(Keys.held_keys(actor, fleet_id)) ->
        %{label: "Message", path: KeyLinks.dm_path(fleet_id, held.token_id, token_id)}

      true ->
        nil
    end
  end

  def message_link(_actor, _owner, _fleet_id, _token_id), do: nil

  @doc """
  What the page shows for the address: one Key's inbox (`:dms`), or its
  conversation with another Key (`:dm`). Someone who doesn't hold the Key now
  is told so, and nothing of its messages is read.
  """
  def read_dms(socket, route_id, fleet_id, token_id, other_token_id) do
    case PageRead.run("messages", fn ->
           show(socket, route_id, fleet_id, token_id, other_token_id)
         end) do
      {:ok, socket} ->
        socket

      {:error, _failure} ->
        socket
        |> assign(dms: :unreadable, dm_form: nil, dm_notice: nil)
        |> stream(:dm_thread, [], reset: true)
    end
  end

  defp show(socket, route_id, fleet_id, token_id, other_token_id) do
    actor = ShellLive.human_actor(socket)

    shown = %{
      fleet_id: fleet_id,
      token_id: token_id,
      other_token_id: other_token_id,
      fleet_name: fleet_name(fleet_id),
      refreshing?: not Chain.fresh?(fleet_id),
      signed_in?: actor != nil,
      holder?: false
    }

    socket
    |> assign(:dm_notice, nil)
    |> show_view(route_id, shown, actor)
  end

  defp show_view(socket, :dms, shown, actor) do
    case read_inbox(shown, actor) do
      {:ok, inbox} -> assign(socket, dms: Map.merge(shown, inbox), dm_form: nil)
      :closed -> assign(socket, dms: shown, dm_form: nil)
    end
  end

  defp show_view(socket, :dm, %{fleet_name: nil} = shown, _actor), do: close(socket, shown)

  defp show_view(socket, :dm, shown, actor) do
    %{fleet_id: fleet_id, token_id: token_id, other_token_id: other} = shown

    case Dms.get_conversation(fleet_id, token_id, other, actor: actor) do
      {:ok, conversation} -> open_conversation(socket, shown, conversation, actor)
      {:error, %Ash.Error.Forbidden{}} -> close(socket, shown)
      {:error, failure} -> raise failure
    end
  end

  defp close(socket, shown) do
    socket
    |> assign(dms: shown, dm_form: nil)
    |> stream(:dm_thread, [], reset: true)
  end

  defp open_conversation(socket, shown, conversation, actor) do
    %{fleet_id: fleet_id, token_id: token_id, other_token_id: other} = shown
    block = Dms.get_block!(fleet_id, token_id, other, actor: actor)

    messages =
      fleet_id
      |> Dms.latest_in_conversation!(token_id, other, %{limit: @thread_page}, actor: actor)
      |> Enum.reverse()

    socket
    |> assign(
      :dms,
      Map.merge(shown, %{
        holder?: true,
        conversation: conversation,
        blocked?: block != nil,
        last_seq: last_seq(messages, 0)
      })
    )
    |> new_form()
    |> stream(:dm_thread, messages, reset: true, limit: -@thread_kept)
    |> mark_read(actor)
  end

  defp read_inbox(%{fleet_name: nil}, _actor), do: :closed

  defp read_inbox(%{fleet_id: fleet_id, token_id: token_id}, actor) do
    with {:ok, conversations} <- Dms.inbox(fleet_id, token_id, actor: actor),
         {:ok, blocked} <- Dms.inbox(fleet_id, token_id, %{blocked: true}, actor: actor),
         {:ok, marks} <- read_marks(conversations ++ blocked, actor) do
      {:ok,
       %{
         holder?: true,
         conversations: conversations,
         blocked: blocked,
         read_to: Map.new(marks, &{&1.conversation_id, &1.seq})
       }}
    else
      {:error, %Ash.Error.Forbidden{}} -> :closed
      {:error, failure} -> raise failure
    end
  end

  defp fleet_name(fleet_id) do
    case Enum.find(Fleets.catalog(), &(&1.id == fleet_id)) do
      %{name: name} -> name
      nil -> nil
    end
  end

  # A message is sent as the Key on show to the other Key, with a fresh key
  # that settles a repeat here rather than in the browser. Only the words come
  # from the box; the key stays with it until a message goes through, so
  # sending again after a refusal can never send twice.
  defp new_form(%{assigns: %{dms: dms}} = socket) do
    server_side = %{
      "fleet_id" => dms.fleet_id,
      "from_token_id" => dms.token_id,
      "to_token_id" => dms.other_token_id,
      "idempotency_key" => Ash.UUID.generate()
    }

    form =
      AshPhoenix.Form.for_create(Message, :send,
        actor: ShellLive.human_actor(socket),
        as: "dm",
        transform_params: fn params, _action ->
          params |> Map.take(["body"]) |> Map.merge(server_side)
        end
      )

    assign(socket, :dm_form, to_form(form))
  end

  @doc "What the conversation page does with a message, its settings, a block and a delete."
  def handle_event(
        "validate_dm",
        %{"dm" => %{"body" => body} = params},
        %{assigns: %{dm_form: %{}}} = socket
      )
      when is_binary(body) do
    {:noreply,
     update(socket, :dm_form, &(&1 |> as_signed_in(socket) |> AshPhoenix.Form.validate(params)))}
  end

  def handle_event(
        "send_dm",
        %{"dm" => %{"body" => body} = params},
        %{assigns: %{dm_form: %{}}} = socket
      )
      when is_binary(body) do
    case socket.assigns.dm_form
         |> as_signed_in(socket)
         |> AshPhoenix.Form.submit(params: params) do
      {:ok, _message} ->
        {:noreply, socket |> assign(:dm_notice, nil) |> new_form() |> show_new_messages()}

      {:error, form} ->
        case Ash.Error.to_error_class(form.source.source.errors) do
          %Ash.Error.Forbidden{} ->
            {:noreply, refused(socket)}

          refusal ->
            {:noreply,
             assign(socket, dm_form: form, dm_notice: send_refusal(refusal, socket.assigns.dms))}
        end
    end
  end

  def handle_event(
        "dm_auto_delete",
        %{"days" => days},
        %{assigns: %{dms: %{conversation: %{}}}} = socket
      )
      when is_binary(days) do
    %{dms: dms} = socket.assigns
    days = if days == "", do: nil, else: days

    case Dms.set_auto_delete(dms.conversation, dms.token_id, days,
           actor: ShellLive.human_actor(socket)
         ) do
      {:ok, conversation} ->
        {:noreply, assign(socket, dms: %{dms | conversation: conversation}, dm_notice: nil)}

      {:error, error} ->
        {:noreply, failed(socket, error)}
    end
  end

  def handle_event(event, _params, %{assigns: %{dms: %{blocked?: _} = dms}} = socket)
      when event in ["dm_block", "dm_unblock"] do
    case change_block(event, dms, ShellLive.human_actor(socket)) do
      {:ok, _block} ->
        {:noreply, assign(socket, dms: %{dms | blocked?: event == "dm_block"}, dm_notice: nil)}

      {:error, error} ->
        {:noreply, failed(socket, error)}
    end
  end

  def handle_event("dm_delete", _params, %{assigns: %{dms: %{conversation: %{}} = dms}} = socket) do
    case Dms.delete_conversation(dms.conversation, dms.token_id,
           actor: ShellLive.human_actor(socket)
         ) do
      {:ok, _cleared} ->
        {:noreply, push_patch(socket, to: inbox_path(dms))}

      {:error, error} ->
        {:noreply, failed(socket, error)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The box sends as the person signed in when it is pressed, read again for
  # every event, never as the one it was drawn for.
  defp as_signed_in(form, socket),
    do:
      AshPhoenix.Form.update_options(
        form,
        &Keyword.put(&1, :actor, ShellLive.human_actor(socket))
      )

  # Every action asks again who holds the Key. One refused because the person
  # no longer holds it closes the page; anything else is said under the box.
  defp failed(socket, %Ash.Error.Forbidden{}), do: refused(socket)
  defp failed(socket, _error), do: assign(socket, :dm_notice, @failed)

  # While Key ownership is being brought up to date nobody holds anything yet,
  # so the page stays and says so; otherwise the Key has changed hands.
  defp refused(%{assigns: %{dms: dms}} = socket) do
    if Chain.fresh?(dms.fleet_id) do
      socket
      |> assign(:dm_notice, nil)
      |> close(%{
        fleet_id: dms.fleet_id,
        token_id: dms.token_id,
        other_token_id: dms.other_token_id,
        fleet_name: dms.fleet_name,
        refreshing?: false,
        signed_in?: true,
        holder?: false
      })
    else
      assign(socket, :dm_notice, KeysLive.refreshing())
    end
  end

  defp change_block("dm_block", dms, actor),
    do: Dms.block_key(dms.fleet_id, dms.token_id, dms.other_token_id, actor: actor)

  defp change_block("dm_unblock", dms, actor),
    do: Dms.unblock_key(dms.fleet_id, dms.token_id, dms.other_token_id, actor: actor)

  @doc """
  A new or deleted conversation of the Key on show. The inbox reads itself
  again; the open conversation reads only the messages after the last one it
  shows, or empties when it was the one deleted.
  """
  def handle_info(%Broadcast{event: "dm_head", payload: %{seq: seq} = head}, socket) do
    case socket.assigns.dms do
      %{holder?: true, conversation: _} = dms when seq > dms.last_seq ->
        {:noreply, if(in_conversation?(dms, head), do: show_new_messages(socket), else: socket)}

      %{holder?: true, conversations: _} ->
        {:noreply, reread_inbox(socket)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_info(%Broadcast{event: "dm_deleted", payload: %{conversation_id: id}}, socket) do
    case socket.assigns.dms do
      %{holder?: true, conversation: %{id: ^id}} = dms ->
        {:noreply,
         socket
         |> assign(
           dms: %{dms | conversation: nil, last_seq: 0},
           dm_notice: "This conversation was deleted."
         )
         |> stream(:dm_thread, [], reset: true)}

      %{holder?: true, conversations: _} ->
        {:noreply, reread_inbox(socket)}

      _other ->
        {:noreply, socket}
    end
  end

  # Before its first message the conversation on show has no id yet, and any
  # new message may be the one that opens it.
  defp in_conversation?(%{conversation: nil}, _head), do: true
  defp in_conversation?(%{conversation: %{id: id}}, %{conversation_id: id}), do: true
  defp in_conversation?(_dms, _head), do: false

  defp reread_inbox(%{assigns: %{dms: dms}} = socket) do
    case read_inbox(dms, ShellLive.human_actor(socket)) do
      {:ok, inbox} -> assign(socket, :dms, Map.merge(dms, inbox))
      :closed -> assign(socket, :dms, %{dms | holder?: false})
    end
  end

  # Only the messages after the last one on the page are read and added to it.
  # The conversation is read again too, so a first message gives the page the
  # conversation it opened.
  defp show_new_messages(%{assigns: %{dms: dms}} = socket) do
    actor = ShellLive.human_actor(socket)
    %{fleet_id: fleet_id, token_id: token_id, other_token_id: other} = dms

    with {:ok, messages} <-
           Dms.read_conversation(fleet_id, token_id, other, %{after_seq: dms.last_seq},
             actor: actor
           ),
         {:ok, conversation} <- Dms.get_conversation(fleet_id, token_id, other, actor: actor) do
      socket
      |> assign(:dms, %{
        dms
        | conversation: conversation,
          last_seq: last_seq(messages, dms.last_seq)
      })
      |> stream(:dm_thread, messages, limit: -@thread_kept)
    else
      {:error, %Ash.Error.Forbidden{}} -> refused(socket)
      {:error, failure} -> raise failure
    end
  end

  defp last_seq([], shown), do: shown
  defp last_seq(messages, _shown), do: List.last(messages).seq

  defp read_marks([], _actor), do: {:ok, []}

  defp read_marks(conversations, actor),
    do: Dms.conversation_read_marks(Enum.map(conversations, & &1.id), actor: actor)

  @doc """
  The person leaves the open conversation, by going to another page or
  closing this one: it is read up to the last message the page showed.
  """
  def leave(socket), do: mark_read(socket, ShellLive.human_actor(socket))

  # The open conversation is read up to the last message the page has shown.
  # It is written when the conversation opens and when the person leaves it,
  # not as messages arrive. When it can't be saved the conversation still
  # opens, and the person still leaves.
  defp mark_read(%{assigns: %{dms: %{conversation: %{id: id}, last_seq: seq}}} = socket, actor)
       when seq > 0 do
    PageRead.run("messages", fn -> Dms.mark_conversation_read!(id, seq, actor: actor) end)
    socket
  end

  defp mark_read(socket, _actor), do: socket

  # Why a message didn't go through, in the line kept for it under the box.
  defp send_refusal(refusal, dms) do
    case refusal do
      %Ash.Error.Invalid{errors: errors} ->
        cond do
          Enum.any?(errors, &match?(%SendLimitError{}, &1)) ->
            "This Key has sent 300 messages in the last hour. Try again later."

          Enum.any?(errors, &match?(%KeyUnknownError{}, &1)) ->
            "Key #{Rules.grouped(dms.other_token_id)} isn’t sold yet."

          most = RoomsLive.too_long(errors) ->
            "A message can be up to #{Rules.grouped(most)} characters."

          Enum.any?(errors, &match?(%{field: :body}, &1)) ->
            "Write a message first."

          true ->
            @failed
        end

      _other ->
        @failed
    end
  end
end
