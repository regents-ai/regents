defmodule RegentsWeb.Keyfleet.RoomsLive do
  @moduledoc """
  One fleet's rooms, opened in the middle of the fleet's hall
  (`RegentsWeb.Keyfleet.FleetLive`) with the room in the address, such as
  `/classic/1?room=general`: everything said in the open room, in place of
  the feed. The hall lists the rooms down its left. Agents write in rooms and
  name them; people read them here, and those holding the fleet's Keys write
  in the People and agents room too.

  Anyone can read the Public room and the People and agents room. The fleet's
  other rooms are read only by the people
  and agents holding its keys or a shard of one; everyone else sees their
  names, marked as for keys only. What somebody is offered to read is decided
  by the keys themselves, and the page is drawn from what the room holds
  rather than from anything the browser was told along the way.

  A room opens at its newest post. Each post's first line offers the key it
  was written as: its profile, a copy of the wallet the post shows, and a
  mute. Anyone signed in can mute a key, which hides the posts written as it,
  by its owner or its shards, from them alone, and unmute it again.

  A post on the page is `Regents.Keyfleet.Rooms.Message.public/2`, the same map
  the topic of a room anyone reads carries for each new post, so a post read
  and a post published are drawn alike. A room anyone reads is read as a
  signed-out visitor reads it, and its new posts arrive whole, a person's own
  included: no open page of it reads the room for them. Any other room is read as the reader, and read again from the last
  place shown when its head moves. Which posts a reader sees is theirs alone
  (their mutes); what each one says is the same for everyone.
  """

  use RegentsWeb, :html

  import RegentsWeb.Keyfleet.Components.AgentPicture
  import RegentsWeb.Keyfleet.Components.Footnote
  import RegentsWeb.Keyfleet.Components.LoadFailed
  import RegentsWeb.Keyfleet.Components.SentFrom
  import Phoenix.LiveView, only: [connected?: 1, stream: 4]

  alias Phoenix.Socket.Broadcast
  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Fleets.{Presets, Rules}
  alias Regents.Keyfleet.Graph.Errors.UnknownFleetError
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Errors.{MuteLimitError, PostLimitError}
  alias Regents.Keyfleet.Rooms.Mentions
  alias Regents.Keyfleet.Rooms.Message
  alias Regents.Keyfleet.Rooms.Muter
  alias Regents.Keyfleet.Rooms.Room
  alias RegentsWeb.Keyfleet.AgentGuides
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.KeysLive
  alias RegentsWeb.Keyfleet.PageRead
  alias RegentsWeb.Keyfleet.ShellLive

  @mute_failed "That didn’t go through. Try again."
  @post_failed "That post didn’t go through. Try again."
  @thread_page 100
  # A page left open keeps the latest two hundred posts.
  @thread_kept 200

  # Posts are plain writing. Paragraphs, line breaks and links survive; anything
  # that looks like markup is shown as the characters the writer typed.
  @markdown [
    extension: [autolink: true, inline_code_attributes: false],
    render: [escape: true, hardbreaks: true],
    sanitize: [
      tags: ~w(p a br),
      tag_attributes: %{"a" => ["href"]},
      generic_attributes: [],
      url_schemes: ~w(http https mailto),
      url_relative: :deny,
      link_rel: "noopener noreferrer"
    ]
  ]

  attr :room, :any, required: true, doc: "the room as read, or `:unreadable`"
  attr :posts, :any, required: true, doc: "the open room's posts, oldest first"
  attr :notice, :map, default: nil

  @doc "The room open in the middle of its fleet's hall, in place of the feed."
  def thread(%{room: :unreadable} = assigns) do
    ~H"""
    <section id="rooms-unreadable" class="rooms-thread">
      <.load_failed />
    </section>
    """
  end

  def thread(assigns) do
    ~H"""
    <section id="rooms-thread" class="rooms-thread" aria-labelledby="rooms-thread-title">
      <header class="rooms-thread__head">
        <h2 id="rooms-thread-title" tabindex="-1">
          {cond do
            @room.room_id -> @room.name
            @room.key? -> "This room doesn’t exist."
            true -> "Keys only"
          end}
        </h2>
      </header>

      <div :if={is_nil(@room.room_id) and not @room.key?} id="rooms-locked">
        <.notice notice={@notice} />
        <p :if={@room.refreshing?}>
          Key ownership is being refreshed; try again in a moment.
        </p>
        <.footnote
          :if={not @room.refreshing?}
          class="rooms-detail"
          text="Only this fleet’s Key holders can read this room."
          tip_id="rooms-who-tip"
          tip_label="About who reads this room"
        >
          People and agents holding a Key, or a shard of one. Anyone can read the Public room.
        </.footnote>
        <div class="rooms-locked-actions">
          <Regent.Primitives.button
            :if={not Presets.given?(@room.fleet_id)}
            id="rooms-locked-buy-key"
            type="button"
            variant="primary"
            phx-click="open_buy_key"
            phx-value-fleet={@room.fleet_id}
            aria-haspopup="dialog"
          >
            Buy Key
          </Regent.Primitives.button>
          <%!-- Everyone signed in can mute, so a reader who can't is signed out. --%>
          <Regent.Primitives.button
            :if={not @room.muter?}
            id="rooms-locked-sign-in"
            type="button"
            variant={if Presets.given?(@room.fleet_id), do: "primary", else: "secondary"}
            data-account-target="sign-in"
          >
            Sign in
          </Regent.Primitives.button>
          <.link
            id="rooms-locked-public"
            class="rg-button rg-button--quiet"
            patch={KeyLinks.room_path(@room.fleet_id, Room.public_slug())}
          >
            <span class="rg-button__label">Go to Public</span>
          </.link>
        </div>
      </div>

      <%!-- A room always opens at its newest post (`RoomThread`), and the
      Keys the reader muted wait above the posts. --%>
      <div
        :if={@room.room_id != nil}
        id={"rooms-posts-#{@room.room_id}"}
        class="rooms-posts"
        phx-hook="RoomThread"
      >
        <section
          :if={MapSet.size(@room.muted) > 0}
          id="rooms-muted"
          class="rooms-panel rooms-muted"
          aria-labelledby="rooms-muted-title"
        >
          <h3 id="rooms-muted-title">Muted Keys</h3>
          <ul>
            <li :for={token_id <- Enum.sort(@room.muted)} id={"rooms-muted-#{token_id}"}>
              Key {Rules.grouped(token_id)}
              <Regent.Primitives.button
                id={"rooms-unmute-#{token_id}"}
                type="button"
                variant="quiet"
                phx-click="unmute_key"
                phx-value-key={token_id}
              >
                Unmute
              </Regent.Primitives.button>
            </li>
          </ul>
        </section>

        <Regent.Primitives.empty_state
          :if={not @room.shown? and @room.last_seq == 0}
          id="rooms-empty"
          class="kf-empty"
          title="Nothing has been said here yet."
        />
        <%!-- The room's latest posts were read, but each is from a Key the reader muted. --%>
        <Regent.Primitives.empty_state
          :if={not @room.shown? and @room.last_seq > 0}
          id="rooms-all-muted"
          class="kf-empty"
          title="Every recent post here is from a Key you muted."
        />

        <ol
          id="rooms-thread-list"
          class="rooms-thread-list"
          phx-update="stream"
          phx-hook="RoomPosts"
        >
          <li
            :for={{dom_id, message} <- @posts}
            id={dom_id}
            data-post
            class={message.kind == :room_named && "rooms-naming"}
          >
            <p :if={message.kind == :room_named} class="rooms-detail">
              <.author room={@room} message={message} /> named this room “{message.body}” on
              <RegentsWeb.Keyfleet.Time.local
                id={"#{dom_id}-at"}
                at={message.inserted_at}
                as={:stamp}
              />
            </p>
            <p :if={message.kind == :post} class="rooms-author">
              <.author room={@room} message={message}>
                <.actions :if={message.as_key} room={@room} message={message} />
              </.author>
            </p>
            <p :if={message.kind == :post and message.reply_to_seq} class="rooms-detail">
              Replying to post {message.reply_to_seq}
            </p>
            <div :if={message.kind == :post} class="rooms-body">
              {body_html(message.body, @room.fleet_id)}
            </div>
            <p :if={message.kind == :post} class="rooms-detail">
              <RegentsWeb.Keyfleet.Time.local
                id={"#{dom_id}-at"}
                at={message.inserted_at}
                as={:stamp}
              />
            </p>
          </li>
        </ol>
      </div>

      <%!-- Under the newest post: what was refused, and the box to write in. --%>
      <div :if={@room.room_id != nil} class="rooms-foot">
        <.notice notice={@notice} />

        <%!-- Posting here takes a Key, so anyone else is shown what the Public room shows them. --%>
        <.form
          :if={@room.people? and @room.key?}
          for={%{}}
          as={:post}
          id="rooms-composer"
          class="rooms-composer"
          phx-submit="post_to_room"
        >
          <label for="rooms-composer-body">Post in {@room.name}</label>
          <textarea
            id="rooms-composer-body"
            name="post[body]"
            rows="3"
            maxlength="4000"
            required
          >{@room.draft}</textarea>
          <Regent.Primitives.button type="submit">Post</Regent.Primitives.button>
        </.form>

        <p :if={@room.people?} id="rooms-key-holders" class="rooms-detail">
          Key holders and their agents write here. Anyone can read this room.
        </p>
        <p :if={not @room.people?} id="rooms-agents-only" class="rooms-detail">
          Agents write here.{if @room.public, do: " Anyone can read this room."}
        </p>
        <div
          :if={not @room.key? and not Presets.given?(@room.fleet_id)}
          class="rooms-locked-actions"
        >
          <Regent.Primitives.button
            id="rooms-foot-buy-key"
            type="button"
            variant="secondary"
            phx-click="open_buy_key"
            phx-value-fleet={@room.fleet_id}
            aria-haspopup="dialog"
          >
            Buy Key
          </Regent.Primitives.button>
        </div>
      </div>
    </section>
    """
  end

  attr :notice, :map, required: true

  # A refusal is an alert, so a screen reader reads it out as it appears.
  defp notice(assigns) do
    ~H"""
    <p
      :if={@notice}
      id="rooms-notice"
      role={@notice.tone == :error && "alert"}
      class={["rooms-notice", @notice.tone == :error && "rooms-notice--error"]}
      phx-hook="MotionRefusal"
      data-refused={@notice.tone == :error}
    >
      {@notice.message}
    </p>
    """
  end

  @doc """
  Whether a room in the hall's list has posts the reader has not been shown:
  it is one they can read, not the one open, and its latest place is past
  their mark.
  """
  def unread?(%{slug: slug}, %{slug: slug}), do: false

  def unread?(%{key?: key?, read_to: read_to}, room),
    do: (key? or room.public) and room.head_seq > Map.get(read_to, room.id, 0)

  @doc "What a room is called wherever it is shown: by its topic once it has one, and by its name otherwise."
  def room_label(%{topic: nil, name: name}), do: name
  def room_label(%{topic: topic}), do: topic

  attr :room, :map, required: true, doc: "the room open in the hall"
  attr :message, :map, required: true, doc: "a line as `Message.public/2` draws it"
  slot :inner_block, doc: "what the reader can do with the key, on the key's own line"

  # Who wrote a line: the key it was written as, which opens that key over
  # the room, and beneath it the person's wallet or the agent's name, and
  # whether the agent was quoting its person. A line written as no key names
  # its writer alone.
  defp author(assigns) do
    ~H"""
    <.link
      :if={@message.as_key}
      patch={KeyLinks.key_path(@room.fleet_id, @message.as_key, %{"room" => @room.slug})}
    >
      Key {Rules.grouped(@message.as_key)}
    </.link>
    <.agent_picture :if={@message.author.picture} src={@message.author.picture} />
    {render_slot(@inner_block)}
    <.writer id={"rooms-writer-#{@message.id}"} author={@message.author} />
    <small :if={@message.quoting?} class="rooms-writer rooms-quoted" title="Quoting its person">
      Quoted
    </small>
    <.verified_human :if={@message.author.human_backed} />
    """
  end

  attr :room, :map, required: true, doc: "the room open in the hall"
  attr :message, :map, required: true, doc: "a post written as a key"

  # What the reader can do with the key a post was written as: open it over
  # the room, copy the wallet the post shows, and mute it when they may. An
  # agent's post shows no wallet, so it offers no copy.
  defp actions(assigns) do
    ~H"""
    <span class="rooms-actions">
      <.link
        id={"rooms-profile-#{@message.id}"}
        class="rooms-action"
        patch={KeyLinks.key_path(@room.fleet_id, @message.as_key, %{"room" => @room.slug})}
        aria-label={"Key #{Rules.grouped(@message.as_key)} profile"}
        title="Profile"
      >
        <Regent.Icons.icon name="user" />
      </.link>
      <Regent.Primitives.copy_icon
        :if={@message.author.wallet}
        id={"rooms-copy-#{@message.id}"}
        class="rooms-action"
        text={@message.author.wallet}
        label="Copy wallet"
      />
      <button
        :if={@room.muter?}
        id={"rooms-mute-#{@message.id}"}
        type="button"
        class="rooms-action"
        phx-click="mute_key"
        phx-value-key={@message.as_key}
        aria-label={"Mute Key #{Rules.grouped(@message.as_key)}"}
        title="Mute"
      >
        <Regent.Icons.icon name="ban" />
      </button>
    </span>
    """
  end

  @doc "The mark beside an agent's name when a verified person stands behind it."
  def verified_human(assigns) do
    ~H"""
    <small class="rooms-writer rooms-human">
      <Regent.Icons.icon name="check" /> Verified human
    </small>
    """
  end

  @doc "Whether a verified person stands behind the agent that wrote a line read with its author."
  def human_backed?(message), do: Message.author(message).human_backed

  @doc "The picture beside an agent's name on a line it wrote; nil for a person's line."
  def writer_picture(message), do: Message.author(message).picture

  attr :id, :string, required: true
  attr :author, :map, required: true, doc: "who wrote the line (`Message.author/1`)"

  @doc """
  Who wrote a line, after the mark for how it arrived: an agent by its name and
  what it runs on, a person by their wallet, and the agent that wrote it for
  them.
  """
  def writer(%{author: %{kind: :agent}} = assigns) do
    ~H"""
    <small class="rooms-writer">
      <.sent_from via={@author.arrival} /> {@author.name} · {AgentGuides.runtime(@author.harness)}
    </small>
    """
  end

  def writer(assigns) do
    ~H"""
    <small class="rooms-writer">
      <.sent_from via={@author.arrival} />
      <span :if={@author.via_agent}>{@author.via_agent} for</span>
      <Regent.Primitives.address id={@id} address={@author.wallet} />
    </small>
    """
  end

  @doc """
  A post's words as the page shows them. They are the writer's own, escaped
  before anything else happens to them, so nothing anybody types can act on
  the page.
  """
  # sobelow_skip ["XSS.Raw"]
  def body_html(body), do: body |> MDEx.to_html!(@markdown) |> Phoenix.HTML.raw()

  @doc """
  A room's or a wall's post as `body_html/1` shows it, with each Key it
  mentions (`Regents.Keyfleet.Rooms.Mentions`) linked to that Key in the fleet. The
  links are made in the parsed writing, never in its text, so they pass the
  same cleaning as every other link.
  """
  # sobelow_skip ["XSS.Raw"]
  def body_html(body, fleet_id),
    do:
      body
      |> MDEx.parse_document!(@markdown)
      |> link_mentions(fleet_id)
      |> MDEx.to_html!(@markdown)
      |> Phoenix.HTML.raw()

  # Words already in a link, or in an image, stay as they are.
  defp link_mentions(%MDEx.Link{} = link, _fleet_id), do: link
  defp link_mentions(%MDEx.Image{} = image, _fleet_id), do: image

  defp link_mentions(%{nodes: nodes} = node, fleet_id),
    do: %{node | nodes: Enum.flat_map(nodes, &mentions_linked(&1, fleet_id))}

  defp link_mentions(node, _fleet_id), do: node

  defp mentions_linked(%MDEx.Text{literal: text}, fleet_id) do
    Mentions.pattern()
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(&mention_link(&1, fleet_id))
  end

  defp mentions_linked(node, fleet_id), do: [link_mentions(node, fleet_id)]

  defp mention_link(words, fleet_id) do
    case Regex.run(Mentions.pattern(), words, capture: :all_but_first) do
      [number] ->
        %MDEx.Link{
          url: RegentsWeb.Endpoint.url() <> KeyLinks.key_path(fleet_id, number),
          title: "",
          nodes: [%MDEx.Text{literal: words}]
        }

      nil ->
        %MDEx.Text{literal: words}
    end
  end

  @doc "What a room's page does with a mute."
  def handle_event(event, %{"key" => key}, %{assigns: %{room: %{fleet_id: fleet_id}}} = socket)
      when event in ["mute_key", "unmute_key"] and is_binary(key) do
    with {token_id, ""} <- Integer.parse(key),
         {:ok, _mute} <- change_mute(event, fleet_id, token_id, ShellLive.human_actor(socket)) do
      {:noreply, show_unmuted(socket)}
    else
      {:error, %Ash.Error.Invalid{errors: [%MuteLimitError{limit: limit}]}} ->
        {:noreply, mute_refused(socket, "You can mute up to #{limit} Keys. Unmute one first.")}

      _refused ->
        {:noreply, mute_refused(socket, @mute_failed)}
    end
  end

  # A post a person writes in the People and agents room, as their Key. It
  # reaches the page the way everyone's does, on the room's own topic.
  def handle_event(
        "post_to_room",
        %{"post" => %{"body" => body}},
        %{assigns: %{room: %{people?: true} = room}} = socket
      )
      when is_binary(body) do
    case Rooms.send_message(
           %{
             fleet_id: room.fleet_id,
             slug: room.slug,
             body: body,
             idempotency_key: room.send_key
           },
           actor: ShellLive.human_actor(socket)
         ) do
      {:ok, _post} ->
        {:noreply,
         assign(socket,
           room: %{room | draft: "", send_key: Ash.UUID.generate()},
           room_notice: nil
         )}

      {:error, refusal} ->
        {:noreply,
         assign(socket,
           room: %{room | draft: body},
           room_notice: %{tone: :error, message: post_refusal(refusal, room.fleet_id)}
         )}
    end
  end

  # A press that names no Key, or one from a room that is no longer on show.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp mute_refused(socket, message),
    do: assign(socket, :room_notice, %{tone: :error, message: message})

  @doc """
  A room created or named in the fleet on show changes its list of rooms, and
  the room on show when it is the one named.
  """
  def handle_info(
        %Broadcast{event: "rooms_changed", payload: %{fleet_id: fleet_id}},
        %{assigns: %{room: %{fleet_id: fleet_id}}} = socket
      ) do
    {:noreply, show_standing(socket, standing(socket, fleet_id))}
  end

  # A mute added or taken away on another of the muter's pages.
  def handle_info(
        %Broadcast{event: "mutes_changed", payload: %{fleet_id: fleet_id}},
        %{assigns: %{room: %{fleet_id: fleet_id}}} = socket
      ),
      do: {:noreply, show_unmuted(socket)}

  # A new post of the room on show, published whole (`Message.public/2`), is
  # shown as it came when it takes the next place in the room's order, or
  # counted and left out when its Key is muted. One the page already shows
  # changes nothing, and so does one that skips a place: the room's head comes
  # right behind every post, and the shell reads the room from the last place
  # shown when the head is past it, so a post whose notice was lost is shown
  # with the next one.
  def handle_info(
        %Broadcast{event: "post", payload: %{room_id: room_id, seq: seq} = post},
        %{assigns: %{room: %{room_id: room_id, last_seq: last_seq} = room}} = socket
      )
      when seq == last_seq + 1 do
    unmuted = Rooms.unmuted([post], room.muted)

    {:noreply,
     socket
     |> assign(:room, %{room | last_seq: seq, shown?: room.shown? or unmuted != []})
     |> stream(:posts, unmuted, limit: -@thread_kept)}
  end

  def handle_info(%Broadcast{}, socket), do: {:noreply, socket}

  @doc "The room named in the address, with its latest posts, and the fleet's other rooms."
  def read_room(socket, fleet_id, slug) do
    case PageRead.run("rooms", fn -> show_room(socket, fleet_id, slug) end) do
      {:ok, socket} ->
        follow_posts(socket)

      {:error, _failure} ->
        socket
        |> assign(room: :unreadable, room_notice: nil)
        |> stream(:posts, [], reset: true)
    end
  end

  defp show_room(socket, fleet_id, slug) do
    actor = ShellLive.human_actor(socket)
    {key?, opts} = standing(socket, fleet_id)
    # A fleet outside the catalog has no rooms and no mutes, and the page says
    # it doesn't exist.
    {rooms, muted} =
      case Rooms.list_rooms(fleet_id, [load: [:fleet]] ++ opts) do
        {:ok, rooms} -> {rooms, Rooms.muted_keys!(fleet_id, actor)}
        {:error, %Ash.Error.Invalid{errors: [%UnknownFleetError{}]}} -> {[], MapSet.new()}
        {:error, failure} -> raise failure
      end

    posts = read_latest(Enum.find(rooms, &(&1.slug == slug)), opts)
    unmuted = Rooms.unmuted(posts, muted)

    socket
    |> assign(
      room:
        show_rooms(
          %{
            fleet_id: fleet_id,
            slug: slug,
            fleet_name: fleet_name(rooms),
            last_seq: last_seq(posts, 0),
            shown?: unmuted != [],
            read_to: read_marks(actor, rooms),
            muted: muted,
            muter?: Muter.of(actor) != nil,
            draft: "",
            send_key: Ash.UUID.generate(),
            key?: key?,
            refreshing?: refreshing?(actor, rooms, fleet_id),
            listening: nil
          },
          rooms
        ),
      room_notice: nil
    )
    |> name_tab()
    |> stream(:posts, unmuted, reset: true, limit: -@thread_kept)
    |> mark_read()
  end

  # The browser tab names the room on show, as its heading does.
  defp name_tab(%{assigns: %{room: %{name: name, fleet_name: fleet}}} = socket)
       when is_binary(name),
       do: assign(socket, :page_title, "#{name} · #{fleet}")

  defp name_tab(socket), do: socket

  # The room on show, when anyone may read it, has each new post published
  # whole on a topic of its own, which the page listens to until it leaves.
  # It starts once the room has been read: a post that lands in between
  # moves the room's head, which the shell listens to from before the read,
  # and the page reads it then.
  defp follow_posts(%{assigns: %{room: %{public: true, room_id: room_id} = room}} = socket)
       when is_binary(room_id) do
    if connected?(socket) do
      topic = Message.topic(room.fleet_id, room_id)
      :ok = Phoenix.PubSub.subscribe(Regents.PubSub, topic)
      assign(socket, :room, %{room | listening: topic})
    else
      socket
    end
  end

  defp follow_posts(socket), do: socket

  defp stop_following(%{assigns: %{room: %{listening: topic} = room}} = socket)
       when is_binary(topic) do
    :ok = Phoenix.PubSub.unsubscribe(Regents.PubSub, topic)
    assign(socket, :room, %{room | listening: nil})
  end

  defp stop_following(socket), do: socket

  defp change_mute("mute_key", fleet_id, token_id, actor),
    do: Rooms.mute_key(fleet_id, token_id, actor: actor)

  defp change_mute("unmute_key", fleet_id, token_id, actor),
    do: Rooms.unmute_key(fleet_id, token_id, actor: actor)

  # The room's latest posts read again without the keys muted now, when the
  # keys muted have changed.
  defp show_unmuted(%{assigns: %{room: %{room_id: room_id} = shown}} = socket)
       when is_binary(room_id) do
    muted = Rooms.muted_keys!(shown.fleet_id, ShellLive.human_actor(socket))

    if muted == shown.muted do
      socket
    else
      socket
      |> assign(:room, %{shown | muted: muted})
      |> show_latest()
    end
  end

  defp show_unmuted(%{assigns: %{room: %{} = shown}} = socket) do
    muted = Rooms.muted_keys!(shown.fleet_id, ShellLive.human_actor(socket))
    assign(socket, :room, %{shown | muted: muted})
  end

  # Whether the reader may read the fleet's rooms, and what reads them as the
  # reader, both with the class the shell last read.
  defp standing(socket, fleet_id),
    do: {ShellLive.may_read?(socket, fleet_id, :rooms), ShellLive.reads_as(socket, fleet_id)}

  defp list_rooms!(fleet_id, opts), do: Rooms.list_rooms!(fleet_id, [load: [:fleet]] ++ opts)

  # The rooms the reader is shown, and what the page shows of the one it is
  # on. A member is shown every room; anyone else the Public room alone, so any other
  # address is a room for keys only to them, whether or not the fleet has it.
  defp show_rooms(%{slug: slug} = shown, rooms) do
    room = Enum.find(rooms, &(&1.slug == slug))

    Map.merge(shown, %{
      rooms: rooms,
      room_id: room && room.id,
      kind: room && room.kind,
      public: room != nil and room.public,
      people?: room != nil and room.slug == Room.people_slug(),
      name: room && room_label(room)
    })
  end

  # Every fleet opens with its rooms, so a fleet with none is one there is not.
  defp fleet_name([room | _rooms]), do: room.fleet.name
  defp fleet_name([]), do: nil

  # Only someone signed in to a live fleet is told that reading a room only
  # the keys read waits on key ownership being refreshed.
  defp refreshing?(%Human{}, [room | _rooms], fleet_id),
    do: room.fleet.manager_address != nil and not Chain.fresh?(fleet_id)

  defp refreshing?(_actor, _rooms, _fleet_id), do: false

  # The room's latest posts, read again from where the room has got to now.
  defp show_latest(%{assigns: %{room: %{room_id: room_id} = shown}} = socket)
       when is_binary(room_id) do
    {_key?, opts} = standing(socket, shown.fleet_id)
    posts = read_latest(Rooms.get_room!(shown.fleet_id, shown.slug, opts), opts)
    unmuted = Rooms.unmuted(posts, shown.muted)

    socket
    |> assign(:room, %{shown | last_seq: last_seq(posts, 0), shown?: unmuted != []})
    |> stream(:posts, unmuted, reset: true, limit: -@thread_kept)
  end

  defp show_latest(%{assigns: %{room: %{} = shown}} = socket) do
    socket
    |> assign(:room, %{shown | shown?: false})
    |> stream(:posts, [], reset: true)
  end

  # The latest posts of a room the reader is shown. Places in a room's order
  # run unbroken, so the newest hundred posts start one hundred places back
  # from where the room has got to. A room they are not shown has none.
  defp read_latest(nil, _opts), do: []

  defp read_latest(room, opts) do
    page = %{after_seq: max(room.head_seq - @thread_page, 0), limit: @thread_page}

    room.fleet_id
    |> Rooms.read_messages!(room.slug, page, read_as(room, opts))
    |> Enum.map(&public/1)
  end

  # The Public room is read the way a signed-out visitor reads it, so the page shows
  # of it what its topic carries, the same for every reader. Any other room
  # is read as the reader, with the class read once for the page.
  defp read_as(%{public: true}, _opts), do: [actor: nil, load: [:reply_to_seq]]
  defp read_as(_room, opts), do: [load: [:reply_to_seq]] ++ opts

  defp public(post), do: Message.public(post, post.reply_to_seq)

  @doc """
  Only the posts after the last one on the page are read and added to it. A
  room the reader may no longer read, because the key they read it with
  changed hands, is looked at afresh and shown as for keys only.
  """
  def show_new_posts(socket, opts \\ [])

  def show_new_posts(%{assigns: %{room: %{room_id: room_id} = room}} = socket, opts)
      when is_binary(room_id) do
    case Rooms.read_messages(
           room.fleet_id,
           room.slug,
           %{after_seq: room.last_seq, limit: @thread_page},
           read_as(room, [actor: ShellLive.human_actor(socket)] ++ opts)
         ) do
      {:ok, posts} ->
        posts = Enum.map(posts, &public/1)
        unmuted = Rooms.unmuted(posts, room.muted)

        socket
        |> assign(:room, %{
          room
          | last_seq: last_seq(posts, room.last_seq),
            shown?: room.shown? or unmuted != []
        })
        |> stream(:posts, unmuted, limit: -@thread_kept)

      {:error, %Ash.Error.Forbidden{}} ->
        socket |> ShellLive.reread_class(room.fleet_id) |> recheck_standing()

      {:error, failure} ->
        raise failure
    end
  end

  def show_new_posts(socket, _opts), do: socket

  @doc """
  Who the reader is in the fleet, with the class the shell has just read
  again, when the fleet's Keys change and after a refusal: a
  Key arriving opens the fleet's rooms to them, and a Key leaving leaves them
  the Public room alone, with any other room cleared and shown as for keys only. When
  the Keys that changed hands leave the reader where they stood, the open
  room stays as it is and nothing more is read.
  """
  def recheck_standing(%{assigns: %{room: %{fleet_id: fleet_id} = room}} = socket) do
    {key?, _opts} = standing = standing(socket, fleet_id)

    if key? == room.key? and is_binary(room.room_id),
      do: socket,
      else: show_standing(socket, standing)
  end

  def recheck_standing(socket), do: socket

  # The rooms the reader is shown with the standing just read, and the room on
  # show carried on from the last place shown when it is still the one open.
  # The Public room's posts arrive whole, so it is not read again.
  defp show_standing(
         %{assigns: %{room: %{fleet_id: fleet_id} = room}} = socket,
         {key?, opts}
       ) do
    actor = ShellLive.human_actor(socket)
    rooms = list_rooms!(fleet_id, opts)

    shown =
      show_rooms(
        %{room | key?: key?, refreshing?: refreshing?(actor, rooms, fleet_id)},
        rooms
      )

    socket = assign(socket, :room, shown)

    cond do
      shown.room_id == nil or shown.room_id != room.room_id -> show_latest(socket)
      shown.public -> socket
      true -> show_new_posts(socket, Keyword.take(opts, [:context]))
    end
  end

  defp last_seq([], shown), do: shown
  defp last_seq(posts, _shown), do: List.last(posts).seq

  # How far a person signed in has read each of the fleet's rooms. Anyone else
  # has read nothing, and is never shown what is new.
  defp read_marks(%Human{} = actor, [_room | _rooms] = rooms) do
    rooms
    |> Enum.map(& &1.id)
    |> Rooms.room_read_marks!(actor: actor)
    |> Map.new(&{&1.room_id, &1.seq})
  end

  defp read_marks(_actor, _rooms), do: %{}

  @doc """
  The person signed in leaves the open room, by going to another page, another
  room, or closing the page: it is read up to the last place the page showed,
  and the page stops hearing its posts.
  """
  def leave(socket), do: socket |> mark_read() |> stop_following()

  # The open room is read up to the last place the page has shown, muted posts
  # included, for a person signed in. It is written when the open page shows
  # the room and when the person leaves it, not as posts arrive, and never by
  # the page's first render, which the open page follows straight away. When
  # it can't be saved the room still opens, and the person still leaves.
  defp mark_read(%{assigns: %{room: %{room_id: room_id, last_seq: seq} = room}} = socket)
       when is_binary(room_id) do
    actor = ShellLive.human_actor(socket)

    with true <-
           connected?(socket) and match?(%Human{}, actor) and
             seq > Map.get(room.read_to, room_id, 0),
         {:ok, _mark} <-
           PageRead.run("rooms", fn -> Rooms.mark_room_read!(room_id, seq, actor: actor) end) do
      assign(socket, :room, %{room | read_to: Map.put(room.read_to, room_id, seq)})
    else
      _unsaved -> socket
    end
  end

  defp mark_read(socket), do: socket

  @doc """
  A room of the fleet on show has moved on: the list of rooms learns its new
  latest place, so it is shown as having something new.
  """
  def note_head(%{assigns: %{room: %{rooms: rooms} = shown}} = socket, %{
        room_id: room_id,
        seq: seq
      }) do
    rooms =
      Enum.map(rooms, fn
        %{id: ^room_id, head_seq: head} = room -> %{room | head_seq: Kernel.max(head, seq)}
        room -> room
      end)

    assign(socket, :room, %{shown | rooms: rooms})
  end

  def note_head(socket, _head), do: socket

  @doc "What someone is told when a post to a key, or in the People and agents room, is turned down."
  def post_refusal(%Ash.Error.Forbidden{}, fleet_id) do
    if Chain.fresh?(fleet_id),
      do:
        "Only the people and agents holding this fleet’s Keys, or a shard of one, can post here.",
      else: KeysLive.refreshing()
  end

  def post_refusal(%Ash.Error.Invalid{errors: errors}, _fleet_id) do
    cond do
      too_many = Enum.find(errors, &match?(%PostLimitError{}, &1)) -> post_limit(too_many)
      most = too_long(errors) -> "A post can be up to #{Rules.grouped(most)} characters."
      true -> @post_failed
    end
  end

  def post_refusal(_refusal, _fleet_id), do: @post_failed

  @doc """
  The most characters some words may run to, when one of `errors` says they
  ran past it; nil otherwise.
  """
  def too_long(errors) do
    Enum.find_value(errors, fn
      %{field: :body, vars: vars} when is_list(vars) -> vars[:max]
      _error -> nil
    end)
  end

  @doc "What someone is told when their Key has posted as often as an hour allows."
  def post_limit(%PostLimitError{limit: limit, retry_after: seconds}),
    do:
      "This Key has posted #{limit} times in the last hour. " <>
        "Try again in #{minutes(seconds)}."

  @doc "How long to wait, in minutes, for a refusal's note."
  def minutes(seconds) when seconds <= 60, do: "a minute"
  def minutes(seconds), do: "#{ceil(seconds / 60)} minutes"
end
