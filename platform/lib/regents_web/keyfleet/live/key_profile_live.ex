defmodule RegentsWeb.Keyfleet.KeyProfileLive do
  @moduledoc """
  One key's profile, open over its fleet's page while the address names the
  key: its card beside, first, who holds it, the Key they post as and the
  Key's page on OpenSea, what it has to claim, and the messages written to it
  with a box to write one; then what is known about it, its shards, and what
  it has said in the fleet's Public room, which anyone can read.

  Closing it takes the key out of the address: by going back when the page
  opened it, so Back and Close agree, and by replacing the address when the
  visitor arrived with the key already in it. The next key on sale shows its
  number, level and price, with Buy Key, which opens the fleet's Buy Key
  window above the profile. A Regents Club Key waiting for whoever holds the
  Pass of its number shows Claim.
  """

  use RegentsWeb, :html

  import RegentsWeb.Keyfleet.Components.AgentPicture
  import RegentsWeb.Keyfleet.Components.Countdown

  import Phoenix.LiveView,
    only: [push_patch: 2, start_async: 3, stream: 4, stream_delete_by_dom_id: 3]

  alias Phoenix.Socket.Broadcast
  alias Regents.Keyfleet.Agents.Here
  alias Regents.Keyfleet.Chain.RewardsWaiting
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Fleet
  alias Regents.Keyfleet.Fleets.Rules
  alias Regents.Keyfleet.Keys.Profile
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Message
  alias Regents.Keyfleet.Treasury
  alias Regents.Keyfleet.WalletSteps.Reads
  alias RegentsWeb.Keyfleet.AgentGuides
  alias RegentsWeb.Keyfleet.CheckIns
  alias RegentsWeb.Keyfleet.Components.KeyCard
  alias RegentsWeb.Keyfleet.Components.Placeholder
  alias RegentsWeb.Keyfleet.DmsLive
  alias RegentsWeb.Keyfleet.FleetLive
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.ProposalsPage
  alias RegentsWeb.Keyfleet.RoomsLive
  alias RegentsWeb.Keyfleet.SharedFigures
  alias RegentsWeb.Keyfleet.ShellLive
  alias RegentsWeb.Keyfleet.WalletPanel
  alias RegentsWeb.Keyfleet.WalletWords
  alias RegentsWeb.Motion

  # A key's profile keeps the latest hundred messages written to it.
  @key_thread_kept 100
  @not_removed "That post couldn’t be taken off right now. Try again."

  attr :profile, :map, required: true
  attr :fleet, :map, required: true
  attr :params, :map, required: true, doc: "the fleet page's address, which links keep"
  attr :thread, :any, required: true, doc: "the messages written to the key, oldest first"
  attr :actor, :any, required: true, doc: "the signed-in person, or nil"
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"

  def dialog(assigns) do
    ~H"""
    <Regent.Structure.dialog
      id="key-profile"
      class="key-profile"
      phx-hook="ModalDialog"
      phx-mounted={JS.ignore_attributes(["open", "style"])}
      data-close={@profile.close}
      data-close-event="close_key"
      data-shown={@profile.token_id}
      aria-labelledby="key-profile-title"
    >
      <div class="key-profile__card" tabindex="0">
        <.card profile={@profile} />
        <.traits :if={@profile.issued?} profile={@profile} />
      </div>

      <div class="key-profile__body" data-modal-scroll>
        <header class="key-profile__header">
          <h2 id="key-profile-title" tabindex="-1" data-modal-title>
            Key {Rules.grouped(@profile.token_id)}
          </h2>
          <div class="key-profile__actions">
            <.link
              :if={@profile.dms}
              id="key-profile-dms"
              class="rg-button rg-button--primary"
              patch={@profile.dms.path}
            >
              <span class="rg-button__label">{@profile.dms.label}</span>
            </.link>
            <form method="dialog">
              <Regent.Primitives.button id="key-profile-close" type="submit" variant="secondary">
                Close
              </Regent.Primitives.button>
            </form>
          </div>
        </header>

        <.next_key :if={not @profile.issued?} profile={@profile} />

        <%= if @profile.issued? do %>
          <.holder profile={@profile} params={@params} />
          <.reveal
            :if={is_nil(@profile.traits) and not @profile.draw_ended?}
            profile={@profile}
            fleet={@fleet}
            actor={@actor}
            lease={@lease}
          />
          <.club_claim
            :if={@profile.held_for_pass?}
            profile={@profile}
            fleet={@fleet}
            actor={@actor}
            lease={@lease}
          />
          <.claim
            :if={@profile.yours? or shard_yours?(@profile, @actor)}
            profile={@profile}
            fleet={@fleet}
            actor={@actor}
            lease={@lease}
          />
          <.thread profile={@profile} fleet={@fleet} params={@params} thread={@thread} />
          <.facts profile={@profile} />
          <.shards profile={@profile} />
          <.recent_posts profile={@profile} params={@params} />
        <% end %>
      </div>
    </Regent.Structure.dialog>
    """
  end

  attr :profile, :map, required: true

  # It loads ahead of the map's close-ups behind the dialog.
  defp card(assigns) do
    ~H"""
    <KeyCard.card
      id="key-profile-card"
      class="key-profile-card"
      src={@profile.image}
      alt={"The card of Key #{Rules.grouped(@profile.token_id)}"}
    />
    """
  end

  attr :profile, :map, required: true

  defp traits(assigns) do
    ~H"""
    <section class="key-profile__traits" aria-labelledby="key-profile-traits-title">
      <h3 id="key-profile-traits-title">Traits</h3>
      <p :if={is_nil(@profile.traits)} class="key-profile-muted">
        {if @profile.draw_ended?, do: "Never gets traits", else: "Revealing"}
      </p>
      <ul :if={@profile.traits} class="key-profile-traits">
        <li :for={trait <- @profile.traits}>
          {trait.trait}: {trait.value}
          <span class="key-profile-muted">({share(trait.share)} of Keys)</span>
        </li>
      </ul>
    </section>
    """
  end

  attr :profile, :map, required: true

  # The Key on sale. Buy Key opens the fleet's Buy Key window above the
  # profile, and closing the window comes back to it.
  defp next_key(assigns) do
    ~H"""
    <section class="key-profile__section" aria-labelledby="key-profile-next-title">
      <h3 id="key-profile-next-title">On sale</h3>
      <dl class="key-profile-facts">
        <div :if={@profile.level}>
          <dt>Level</dt>
          <dd>{@profile.level}</dd>
        </div>
        <div>
          <dt>Price</dt>
          <dd>{FleetLive.usdc(@profile.issue_price)}</dd>
        </div>
      </dl>
      <Regent.Primitives.button
        id="key-profile-buy"
        type="button"
        variant="primary"
        phx-click="open_buy_key"
        phx-value-fleet={@profile.fleet_id}
        aria-haspopup="dialog"
      >
        Buy Key
      </Regent.Primitives.button>
    </section>
    """
  end

  attr :profile, :map, required: true

  defp facts(assigns) do
    ~H"""
    <section class="key-profile__section" aria-labelledby="key-profile-facts-title">
      <h3 id="key-profile-facts-title">Overview</h3>
      <dl class="key-profile-facts">
        <div :if={@profile.level}>
          <dt>Level</dt>
          <dd>{@profile.level}</dd>
        </div>
        <div :if={@profile.issue_price}>
          <dt>Issued for</dt>
          <dd>{FleetLive.usdc(@profile.issue_price)}</dd>
        </div>
        <div>
          <dt>Rewards waiting</dt>
          <dd
            id="key-profile-rewards"
            aria-live="polite"
            phx-hook="MotionCount"
            data-variant={Motion.standard("count")}
          >
            <.rewards rewards={@profile.rewards} />
          </dd>
        </div>
        <div>
          <dt>Treasury slice</dt>
          <dd id="key-profile-slice"><.slice slice={@profile.slice} /></dd>
        </div>
        <div>
          <dt>Held since</dt>
          <dd id="key-profile-held-since">{day(@profile.held_since)}</dd>
        </div>
        <div>
          <dt>Changed hands</dt>
          <dd>{times(@profile.changed_hands)}</dd>
        </div>
        <div>
          <dt>Votes cast</dt>
          <dd id="key-profile-votes" phx-hook="MotionCount" data-variant={Motion.standard("count")}>
            <span data-count>{Rules.grouped(@profile.votes_cast)}</span>
          </dd>
        </div>
        <div>
          <dt>Public posts</dt>
          <dd id="key-profile-posts">{Rules.grouped(@profile.posts)}</dd>
        </div>
        <div>
          <dt>Wall posts</dt>
          <dd id="key-profile-messages">{Rules.grouped(@profile.messages)}</dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :profile, :map, required: true

  # The agents lent a shard of the Key, one row each.
  defp shards(assigns) do
    ~H"""
    <section class="key-profile__section" aria-labelledby="key-profile-shards-title">
      <div class="key-profile__section-head">
        <h3 id="key-profile-shards-title">Shards</h3>
        <.link
          :if={@profile.yours?}
          id="key-profile-manage"
          patch={KeyLinks.page_path(@profile.fleet_id, @profile.token_id)}
        >
          Manage shards
        </.link>
      </div>
      <p :if={@profile.shards == []} id="key-profile-shards" class="key-profile-muted">None</p>
      <ul :if={@profile.shards != []} id="key-profile-shards" class="key-profile-shards">
        <li :for={shard <- @profile.shards} id={"key-profile-shard-#{shard.wallet}"}>
          <.shard_agent shard={shard} seen={@profile.seen[shard.wallet]} />
          <span class="key-profile-status">Lent until {day(shard.expires_at)}</span>
        </li>
      </ul>
    </section>
    """
  end

  attr :shard, :map, required: true

  attr :seen, :map,
    default: nil,
    doc: "what the agent's check-ins say, as every page shares it"

  # The agent holding a shard, as its check-ins say, or its wallet while no
  # agent has signed in with it.
  defp shard_agent(%{shard: %{agent: nil}} = assigns),
    do:
      ~H|<Regent.Primitives.address id={"key-profile-shard-address-#{@shard.wallet}"} address={@shard.wallet} />|

  defp shard_agent(assigns) do
    ~H"""
    <span class="key-profile-shard__who">
      <.agent_picture src={@shard.agent.avatar_src} />
      <strong>{@shard.agent.name}</strong>
      <span class="key-profile-muted">{AgentGuides.runtime(@shard.agent.harness)}</span>
    </span>
    <a
      :if={@shard.agent.registry_url}
      id={"key-profile-registry-#{@shard.wallet}"}
      href={@shard.agent.registry_url}
      target="_blank"
      rel="noopener"
    >
      Registry listing
    </a>
    <.human_backing wallet={@shard.wallet} agent={@shard.agent} />
    <CheckIns.status
      id={"key-profile-check-in-#{@shard.wallet}"}
      class="key-profile-status"
      seen={@seen}
    />
    <span :if={@shard.agent.status != ""} class="key-profile-status">
      “{@shard.agent.status}”, {day(@shard.agent.status_updated_at)}
    </span>
    """
  end

  attr :wallet, :string, required: true
  attr :agent, :map, required: true

  # Two states only: a person verified with World ID stands behind the agent,
  # or none does. What each means waits in its tip; who the person is never
  # shows.
  defp human_backing(%{agent: %{backing: %{human_backed: true}}} = assigns) do
    ~H"""
    <span id={"key-profile-human-#{@wallet}"} class="key-profile-status">
      <Regent.Icons.icon name="check" /> Verified human
      <Regent.Primitives.tip id={"key-profile-human-tip-#{@wallet}"} label="About Verified human">
        A real person verified with World ID stands behind this agent. Who they are stays private.
      </Regent.Primitives.tip>
    </span>
    <span
      :if={@agent.backing.same_person_agent_count >= 2}
      id={"key-profile-same-person-#{@wallet}"}
      class="key-profile-status"
    >
      1 of {@agent.backing.same_person_agent_count} agents run by the same person{same_person(
        @agent.same_person
      )}
    </span>
    """
  end

  defp human_backing(assigns) do
    ~H"""
    <span id={"key-profile-human-#{@wallet}"} class="key-profile-status">
      No verified human
      <Regent.Primitives.tip id={"key-profile-human-tip-#{@wallet}"} label="About No verified human">
        The agent's person can vouch for it with World ID.
        <a href="https://siwa.regents.sh/skill.md" target="_blank" rel="noopener noreferrer">
          Step 7
        </a>
      </Regent.Primitives.tip>
    </span>
    """
  end

  # The same person's other agents Keyfleet knows, by name.
  defp same_person([]), do: ""
  defp same_person(names), do: ", with " <> Enum.join(names, ", ")

  attr :profile, :map, required: true
  attr :fleet, :map, required: true
  attr :actor, :any, required: true
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"

  # What the key has earned and not yet been paid, each token claimed with its
  # own button and always paid to the wallet that holds the key, whether its
  # holder or one of its shards presses.
  defp claim(assigns) do
    ~H"""
    <section
      id="key-profile-claim"
      class="key-profile__section"
      aria-labelledby="key-profile-claim-title"
    >
      <h3 id="key-profile-claim-title">
        Claim
        <Regent.Primitives.tip id="key-profile-claim-tip" label="About claiming">
          The Daily Treasury Slice to Keys shared with this Key waits here until claimed. It is always paid to the Key’s holder, and a shard of the Key can claim it for them.
        </Regent.Primitives.tip>
      </h3>
      <.live_component
        module={WalletPanel}
        names_sender={false}
        id="key-profile-claim-action"
        flow={:claim}
        tool="keys_claim"
        fleet={%{fleet_id: @fleet.fleet_id, chain_id: @fleet.chain_id}}
        actor={@actor}
        lease={@lease}
        token_id={@profile.token_id}
        refresh={@profile.rewards}
      >
        <:buttons :let={panel}>
          <WalletPanel.step_button
            :for={waiting <- waiting(panel)}
            panel={panel}
            step={"claim-#{waiting.asset}"}
            id={"key-profile-claim-#{waiting.asset}"}
          >
            Claim {WalletWords.token_amount(waiting)}
          </WalletPanel.step_button>
        </:buttons>
      </.live_component>
    </section>
    """
  end

  attr :profile, :map, required: true
  attr :fleet, :map, required: true
  attr :actor, :any, required: true
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"

  # A key whose request for its random draw was turned down has no traits
  # until someone asks again, which anyone may do. A draw that hasn't come 24
  # hours after its request was accepted holds the draws' coordinator until
  # someone ends the wait, which anyone may do too; the key then never gets
  # traits. The chain says whether the draw is on its way, done or ended, and
  # each button says so while it can't be pressed.
  defp reveal(assigns) do
    ~H"""
    <section
      id="key-profile-reveal"
      class="key-profile__section"
      aria-labelledby="key-profile-reveal-title"
    >
      <h3 id="key-profile-reveal-title">
        Traits
        <Regent.Primitives.tip id="key-profile-reveal-tip" label="About drawing traits">
          A Key’s traits come from a random draw. If the request for it was turned down, anyone can ask again. If the draw hasn’t come 24 hours after it was asked for, anyone can end the wait, and the Key then never gets traits.
        </Regent.Primitives.tip>
      </h3>
      <.live_component
        module={WalletPanel}
        names_sender={false}
        id="key-profile-reveal-action"
        flow={:reveal}
        fleet={%{fleet_id: @fleet.fleet_id, chain_id: @fleet.chain_id}}
        actor={@actor}
        lease={@lease}
        token_id={@profile.token_id}
      >
        <:buttons :let={panel}>
          <WalletPanel.step_button panel={panel} step="reveal" id="key-profile-reveal-again">
            Ask again
          </WalletPanel.step_button>
          <WalletPanel.step_button
            panel={panel}
            step="expire_reveal"
            id="key-profile-reveal-expire"
            variant="secondary"
          >
            End the wait for good
          </WalletPanel.step_button>
        </:buttons>
      </.live_component>
    </section>
    """
  end

  attr :profile, :map, required: true
  attr :fleet, :map, required: true
  attr :actor, :any, required: true
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"

  # A Regents Club Key waiting for whoever holds the Pass of its number, who
  # takes it with everything it has earned. The chain says whether the signer
  # holds that Pass, and the button says so while they don't.
  defp club_claim(assigns) do
    ~H"""
    <section
      id="key-profile-club-claim"
      class="key-profile__section"
      aria-labelledby="key-profile-club-claim-title"
    >
      <h3 id="key-profile-club-claim-title">
        Unclaimed
        <Regent.Primitives.tip id="key-profile-club-claim-tip" label="About claiming this Key">
          The holder of Regents Club Pass {Rules.grouped(@profile.token_id)} can claim this Key at any time, with everything it has earned while it waited. If that Pass is burned, the Key stays here for good.
        </Regent.Primitives.tip>
      </h3>
      <.live_component
        module={WalletPanel}
        names_sender={false}
        id="key-profile-club-claim-action"
        flow={:club_claim}
        fleet={%{fleet_id: @fleet.fleet_id, chain_id: @fleet.chain_id}}
        actor={@actor}
        lease={@lease}
        token_id={@profile.token_id}
      >
        <:buttons :let={panel}>
          <WalletPanel.step_button panel={panel} step="club-claim" id="key-profile-club-claim-button">
            Claim
          </WalletPanel.step_button>
        </:buttons>
      </.live_component>
    </section>
    """
  end

  defp waiting(panel), do: panel |> WalletPanel.figures() |> Map.get(:waiting, [])

  defp shard_yours?(%{shards: shards}, %{wallet_addresses: wallets}),
    do: Enum.any?(shards, &(&1.wallet in wallets))

  defp shard_yours?(_profile, _actor), do: false

  attr :profile, :map, required: true
  attr :params, :map, required: true

  # Another of the holder's keys, the one they post as among them, opens in
  # place of this one, without adding a step to go back through.
  defp holder(assigns) do
    ~H"""
    <section
      id="key-profile-owner"
      class="key-profile__section"
      aria-labelledby="key-profile-holder-title"
    >
      <div class="key-profile-holder">
        <h3 id="key-profile-holder-title">Held by {held_by(@profile)}</h3>
        <Regent.Primitives.address id="key-profile-holder-address" address={@profile.holder} />
        <a id="key-profile-opensea" href={@profile.opensea} rel="noopener noreferrer" target="_blank">
          View on OpenSea
        </a>
      </div>
      <.link
        :if={not @profile.held_for_pass?}
        id="key-profile-posts-as"
        class="key-profile-posts-as"
        patch={KeyLinks.key_path(@profile.fleet_id, @profile.posts_as.token_id, @params)}
        replace
        aria-current={@profile.posts_as.token_id == @profile.token_id && "true"}
      >
        <img
          :if={@profile.posts_as.image}
          src={@profile.posts_as.image}
          alt=""
          width="40"
          height="50"
          loading="lazy"
          decoding="async"
        />
        <span :if={!@profile.posts_as.image} class="fleet-entry__blank"></span>
        <span class="key-profile-posts-as__words">
          Posts as <strong>Key {Rules.grouped(@profile.posts_as.token_id)}</strong>
        </span>
      </.link>
      <dl class="key-profile-facts">
        <div>
          <dt>Fleet Keys</dt>
          <dd id="key-profile-holder-keys">{Rules.grouped(@profile.holder_key_count)}</dd>
        </div>
        <div>
          <dt>All Keys</dt>
          <dd>{Rules.grouped(@profile.holder_keys_everywhere)}</dd>
        </div>
        <div>
          <dt>Votes</dt>
          <dd
            id="key-profile-holder-votes"
            phx-hook="MotionCount"
            data-variant={Motion.standard("count")}
          >
            <.count value={@profile.holder_votes} noun="vote" /> on
            <.count
              value={@profile.holder_proposals}
              noun="proposal"
            />
          </dd>
        </div>
        <div>
          <dt>Public posts</dt>
          <dd id="key-profile-holder-posts">{Rules.grouped(@profile.holder_posts)}</dd>
        </div>
      </dl>
      <ul class="key-profile-keys" aria-label="Keys in this fleet">
        <li :for={token_id <- @profile.holder_keys}>
          <.link
            id={"key-profile-key-#{token_id}"}
            patch={KeyLinks.key_path(@profile.fleet_id, token_id, @params)}
            replace
            aria-current={token_id == @profile.token_id && "true"}
          >
            Key {Rules.grouped(token_id)}
          </.link>
        </li>
      </ul>
      <p :if={@profile.holder_key_count > length(@profile.holder_keys)} class="key-profile-muted">
        and {Rules.grouped(@profile.holder_key_count - length(@profile.holder_keys))} more
      </p>
    </section>
    """
  end

  attr :profile, :map, required: true
  attr :fleet, :map, required: true
  attr :params, :map, required: true
  attr :thread, :any, required: true

  defp thread(assigns) do
    ~H"""
    <section class="key-profile__section" aria-labelledby="key-profile-thread-title">
      <h3 id="key-profile-thread-title">Wall</h3>
      <Regent.Primitives.empty_state
        :if={@profile.messages == 0}
        class="kf-empty"
        title="Nobody has posted on this wall yet."
      />
      <ol
        id="key-profile-thread"
        class="rooms-thread-list"
        phx-update="stream"
        phx-hook="KeyfleetMotionList"
        data-variant={Motion.standard("list")}
        data-layout-id="key-profile-thread"
        data-children="[data-post]"
      >
        <li :for={{dom_id, message} <- @thread} id={dom_id} data-post data-layout-id={dom_id}>
          <p class="rooms-author">
            <.author fleet_id={@profile.fleet_id} message={message} params={@params} />
            <Regent.Primitives.button
              :if={@profile.yours?}
              id={"key-profile-remove-#{message.id}"}
              class="key-profile-remove"
              type="button"
              variant="quiet"
              phx-click="remove_from_wall"
              phx-value-id={message.id}
              data-confirm="Take this post off your wall? It can’t be put back."
              data-confirm-action="Remove"
              aria-label="Take this post off your wall"
              title="Take this post off your wall"
            >
              <Regent.Icons.icon name="x" />
            </Regent.Primitives.button>
          </p>
          <div class="rooms-body">{RoomsLive.body_html(message.body, @profile.fleet_id)}</div>
          <p class="rooms-detail">
            <RegentsWeb.Keyfleet.Time.local id={"#{dom_id}-at"} at={message.inserted_at} as={:stamp} />
          </p>
        </li>
      </ol>
      <%!-- The stream keeps no rows here, so the page shows this only while the list above is empty. --%>
      <p
        :if={@profile.messages > 0 and MapSet.size(@profile.muted) > 0}
        id="key-profile-muted-hidden"
        class="key-profile-muted key-profile-muted-hidden"
      >
        Posts from Keys you muted are hidden.
      </p>
      <p id="key-profile-news" class="key-profile-news" role="status">{@profile.news}</p>

      <p
        :if={@profile.notice}
        id="key-profile-notice"
        class="rooms-notice rooms-notice--error"
        phx-hook="MotionRefusal"
        data-refused
      >
        {@profile.notice}
      </p>

      <.form
        :if={@profile.composer == :write}
        for={%{}}
        as={:post}
        id="key-profile-composer"
        class="rooms-composer"
        phx-submit="post_to_key"
      >
        <label for="key-profile-composer-body">
          Post on Key {Rules.grouped(@profile.token_id)}’s wall
        </label>
        <textarea
          id="key-profile-composer-body"
          name="post[body]"
          rows="3"
          maxlength="4000"
          required
        >{@profile.draft}</textarea>
        <Regent.Primitives.button type="submit">Post</Regent.Primitives.button>
      </.form>

      <div :if={@profile.composer == :sign_in} class="key-profile__signed-out">
        <p>Everyone can read. Sign in to post on Key {Rules.grouped(@profile.token_id)}’s wall.</p>
        <Regent.Primitives.button type="button" variant="secondary" data-account-target="sign-in">
          Sign in
        </Regent.Primitives.button>
      </div>

      <p :if={@profile.composer == :no_key} class="key-profile-muted">
        Only people who hold a Key in {@fleet.name} can post here. Everyone can read.
      </p>

      <p :if={@profile.composer == :refreshing} class="key-profile-muted">
        Key ownership is being refreshed; try again in a moment.
      </p>
    </section>
    """
  end

  attr :profile, :map, required: true
  attr :params, :map, required: true

  defp recent_posts(assigns) do
    ~H"""
    <section class="key-profile__section" aria-labelledby="key-profile-posts-title">
      <h3 id="key-profile-posts-title">
        Public posts
      </h3>
      <Regent.Primitives.empty_state
        :if={@profile.recent_posts == []}
        class="kf-empty"
        title="This Key hasn’t posted in Public yet."
      />
      <ol :if={@profile.recent_posts != []} id="key-profile-recent" class="rooms-thread-list">
        <li :for={post <- @profile.recent_posts} id={"key-profile-recent-#{post.id}"}>
          <p class="rooms-detail">
            In
            <.link patch={KeyLinks.room_path(@profile.fleet_id, post.room.slug)}>
              {RoomsLive.room_label(post.room)}
            </.link>
            on
            <RegentsWeb.Keyfleet.Time.local
              id={"key-profile-recent-#{post.id}-at"}
              at={post.inserted_at}
              as={:stamp}
            />
          </p>
          <div class="rooms-body">{RoomsLive.body_html(post.body, @profile.fleet_id)}</div>
        </li>
      </ol>
    </section>
    """
  end

  attr :fleet_id, :string, required: true
  attr :message, :map, required: true
  attr :params, :map, required: true

  # Who wrote a message: the key it was written as, which opens in place of
  # this one, and the person's wallet or the agent's name.
  defp author(assigns) do
    ~H"""
    <.link patch={KeyLinks.key_path(@fleet_id, @message.as_key, @params)} replace>
      Key {Rules.grouped(@message.as_key)}
      <.agent_picture
        :if={RoomsLive.writer_picture(@message)}
        src={RoomsLive.writer_picture(@message)}
      />
    </.link>
    <RoomsLive.writer id={"key-profile-writer-#{@message.id}"} author={Message.author(@message)} />
    <RoomsLive.verified_human :if={RoomsLive.human_backed?(@message)} />
    """
  end

  defp held_by(%{yours?: true}), do: "You"

  defp held_by(%{held_for_pass?: true, token_id: token_id}),
    do: "Regents Club, for Pass #{Rules.grouped(token_id)}"

  defp held_by(_profile), do: nil

  attr :rewards, :any, required: true

  # What the key's holder can claim in each asset, read after the window
  # opens. Each amount rolls when more arrives.
  defp rewards(%{rewards: :reading} = assigns),
    do: ~H|<Placeholder.placeholder label="Loading rewards" lines={1} role={nil} />|

  defp rewards(%{rewards: :failed} = assigns),
    do: ~H"Rewards aren’t showing right now. They update on their own."

  defp rewards(%{rewards: {:ok, []}} = assigns), do: ~H"None yet"

  defp rewards(%{rewards: {:ok, amounts}} = assigns) do
    assigns = assign(assigns, :amounts, amounts)
    ~H|<span :for={amount <- @amounts} data-count>{amount.text}</span>|
  end

  attr :slice, :any, required: true

  # When the key first shares the Daily Treasury Slice to Keys, counted down
  # to the second, as the vote contract dates it from the key's mint.
  defp slice(%{slice: :reading} = assigns),
    do: ~H|<Placeholder.placeholder label="Loading the Treasury slice" lines={1} role={nil} />|

  defp slice(%{slice: :failed} = assigns), do: ~H"Not showing right now"

  defp slice(%{slice: {:ok, matures_at, now}} = assigns) do
    assigns = assign(assigns, matures_at: matures_at, now: now)

    ~H"""
    <.countdown
      id="key-profile-slice-countdown"
      closes_at={@matures_at}
      now={@now}
      format="clock"
      lead="Eligible in"
      done="Eligible"
    />
    """
  end

  defp times(0), do: "Never"
  defp times(1), do: "Once"
  defp times(count), do: "#{Rules.grouped(count)} times"

  attr :value, :integer, required: true
  attr :noun, :string, required: true

  # A figure that rolls when it changes, then its noun.
  defp count(assigns),
    do:
      ~H|<span data-count>{Rules.grouped(@value)}</span> {if @value == 1, do: @noun, else: "#{@noun}s"}|

  defp day(datetime), do: Calendar.strftime(datetime, "%-d %B %Y")

  # A share of keys as a percentage, to a tenth where that matters.
  defp share(share) do
    percent = share * 100

    if percent >= 10,
      do: "#{round(percent)}%",
      else: "#{:erlang.float_to_binary(percent, decimals: 1)}%"
  end

  @doc "What the key's profile does with a message written to the key and with Close."
  def handle_event("post_to_key", %{"post" => %{"body" => body}}, socket) when is_binary(body) do
    {:noreply, post_to_key(socket, body)}
  end

  def handle_event("remove_from_wall", %{"id" => message_id}, socket)
      when is_binary(message_id),
      do: {:noreply, remove_from_wall(socket, message_id)}

  # A key the visitor arrived on closes by taking it out of the address in
  # place, so closing adds no step to go back through.
  def handle_event(
        "close_key",
        _params,
        %{assigns: %{key_profile: %{fleet_id: fleet_id}}} = socket
      ) do
    {:noreply,
     push_patch(socket,
       to: KeyLinks.closed_path(fleet_id, socket.assigns.fleet_params),
       replace: true
     )}
  end

  # Close with no key open, or a post or removal that arrives without its words
  # or its post, changes nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @doc """
  Something written as, or to, the open key or another of its holder's keys:
  the key's new messages are read from its thread, and its posts again.
  """
  def handle_info(
        %Broadcast{event: "key_activity", payload: %{fleet_id: fleet_id, token_ids: token_ids}},
        %{assigns: %{key_profile: %{fleet_id: fleet_id, issued?: true} = profile}} = socket
      ) do
    if Enum.any?(token_ids, &(&1 == profile.token_id or &1 in profile.holder_keys)),
      do: {:noreply, show_key_activity(socket)},
      else: {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "key_activity"}, socket), do: {:noreply, socket}

  # A post its holder took off the open key's wall leaves the page.
  def handle_info(
        %Broadcast{
          event: "wall_removed",
          payload: %{fleet_id: fleet_id, token_id: token_id, message_id: message_id}
        },
        %{assigns: %{key_profile: %{fleet_id: fleet_id, token_id: token_id, issued?: true}}} =
          socket
      ),
      do: {:noreply, off_wall(socket, message_id)}

  def handle_info(%Broadcast{event: "wall_removed"}, socket), do: {:noreply, socket}

  @doc "What the key has waiting, once the chain answers. A read for a key no longer open is dropped."
  def handle_async(:rewards, result, %{assigns: %{key_profile: %{issued?: true}}} = socket),
    do: {:noreply, update(socket, :key_profile, &%{&1 | rewards: rewards_shown(result)})}

  def handle_async(:rewards, _result, socket), do: {:noreply, socket}

  def handle_async(:slice, result, %{assigns: %{key_profile: %{issued?: true}}} = socket),
    do: {:noreply, update(socket, :key_profile, &%{&1 | slice: slice_shown(result)})}

  def handle_async(:slice, _result, socket), do: {:noreply, socket}

  @doc "The profile of the key the address names, open over its fleet's page."
  def read_key_profile(socket, fleet, token_id, before) do
    actor = ShellLive.human_actor(socket)
    profile = Profile.read(fleet.fleet_id, token_id, actor)

    socket
    |> assign(
      :key_profile,
      profile
      |> Map.delete(:thread)
      |> Map.merge(%{
        dms: dms(profile, actor),
        close: closing(before, fleet.fleet_id),
        news: nil,
        notice: nil,
        draft: "",
        send_key: Ash.UUID.generate()
      })
    )
    |> follow_seen()
    |> read_rewards(before)
    |> read_slice(before)
    |> stream(:key_thread, key_thread(profile), reset: true, limit: -@key_thread_kept)
  end

  # What an issued key has waiting is read from the chain once the window is
  # open, so the window never waits for the chain. The same key shown again
  # keeps the figure it has.
  defp read_rewards(
         %{assigns: %{key_profile: %{fleet_id: fleet_id, token_id: token_id}}} = socket,
         %{
           key_profile: %{
             fleet_id: fleet_id,
             token_id: token_id,
             rewards: {:ok, _amounts} = shown
           }
         }
       ),
       do: update(socket, :key_profile, &Map.put(&1, :rewards, shown))

  defp read_rewards(%{assigns: %{key_profile: %{issued?: true}}} = socket, _before) do
    socket
    |> update(:key_profile, &Map.put(&1, :rewards, :reading))
    |> start_rewards_read()
  end

  defp read_rewards(socket, _before), do: socket

  @doc """
  What the open key has waiting, read again when income may have reached the
  fleet. The figure on show stays until the chain answers.
  """
  def refresh_rewards(%{assigns: %{key_profile: %{issued?: true}}} = socket),
    do: start_rewards_read(socket)

  def refresh_rewards(socket), do: socket

  defp start_rewards_read(
         %{assigns: %{fleet: fleet, key_profile: %{token_id: token_id, holder: holder}}} = socket
       ) do
    rewards = Map.take(fleet, [:fleet_id, :chain_fleet_id, :rewards_address])

    start_async(socket, :rewards, fn ->
      with {:ok, waiting} <- RewardsWaiting.read(rewards, token_id, holder) do
        {:ok, shown_amounts(fleet.fleet_id, waiting)}
      end
    end)
  end

  # Each asset with something to claim, the key's own and its holder's
  # credit together, as every page shows an amount.
  defp shown_amounts(fleet_id, waiting) do
    assets = fleet_id |> Fleets.get_fleet!() |> Treasury.assets()

    for %{asset: asset, accrued: accrued, credit: credit} <- waiting,
        accrued + credit > 0,
        do: ProposalsPage.amount(accrued + credit, asset, assets)
  end

  defp rewards_shown({:ok, {:ok, amounts}}), do: {:ok, amounts}
  defp rewards_shown(_failed), do: :failed

  # When an issued key first shares the Treasury slice is read from the chain
  # once the window is open. It never moves, so the same key shown again keeps
  # it, counted from the site's clock as it is now.
  defp read_slice(
         %{assigns: %{key_profile: %{fleet_id: fleet_id, token_id: token_id}}} = socket,
         %{
           key_profile: %{fleet_id: fleet_id, token_id: token_id, slice: {:ok, matures_at, _then}}
         }
       ),
       do:
         update(socket, :key_profile, &Map.put(&1, :slice, {:ok, matures_at, DateTime.utc_now()}))

  defp read_slice(
         %{assigns: %{key_profile: %{issued?: true, fleet_id: fleet_id, token_id: token_id}}} =
           socket,
         _before
       ) do
    socket
    |> update(:key_profile, &Map.put(&1, :slice, :reading))
    |> start_async(:slice, fn ->
      fleet = Fleets.get_fleet!(fleet_id)
      onchain = Fleet.onchain_token_id(fleet, token_id)

      with {:ok, reads} <- Reads.at_head(),
           {:ok, matures_at} <-
             Reads.one(reads, fleet.votes_address, "maturesAt(uint256)", [onchain], {:uint, 64}) do
        {:ok, DateTime.from_unix!(matures_at)}
      end
    end)
  end

  defp read_slice(socket, _before), do: socket

  defp slice_shown({:ok, {:ok, matures_at}}), do: {:ok, matures_at, DateTime.utc_now()}
  defp slice_shown(_failed), do: :failed

  # The messages written to a key, leaving out posts written as a key the
  # visitor has muted; the next key on sale has none yet.
  defp key_thread(%{issued?: true, thread: thread, muted: muted}),
    do: Rooms.unmuted(thread, muted)

  defp key_thread(%{issued?: false}), do: []

  # How the profile closes: by going back when the fleet's page opened it, so
  # Close and Back agree; in place when the visitor arrived with the key in
  # the address. Another key opened while a profile is open takes its place in
  # the address rather than adding a step, so it closes as the first one did.
  defp closing(%{fleet: %{fleet_id: fleet_id, chosen_key: nil}}, fleet_id), do: "back"
  defp closing(%{key_profile: %{fleet_id: fleet_id, close: close}}, fleet_id), do: close
  defp closing(_before, _fleet_id), do: "replace"

  @doc """
  The open key is read again when it was sold, or when it or another key
  changed hands to or from its holder. What the visitor was writing stays,
  and the thread keeps its messages. Otherwise its shards are read again when
  it is among the changed keys, and who may write is checked again: the
  visitor may have bought their first key, or the fleet's key ownership become
  fresh.
  """
  def refresh_key_profile(%{assigns: %{key_profile: %{} = shown}} = socket, token_ids) do
    if holder_moved?(shown, token_ids) do
      actor = ShellLive.human_actor(socket)
      profile = Profile.read(shown.fleet_id, shown.token_id, actor)

      socket
      |> assign(
        :key_profile,
        profile
        |> Map.delete(:thread)
        |> Map.merge(Map.take(shown, [:close, :news, :notice, :draft, :send_key]))
        |> Map.put(:dms, dms(profile, actor))
      )
      |> follow_seen()
      |> read_rewards(%{key_profile: shown})
      |> read_slice(%{key_profile: shown})
      |> stream(:key_thread, key_thread(profile), limit: -@key_thread_kept)
    else
      socket
      |> refresh_shards_among(shown.token_id in token_ids)
      |> recheck_composer()
    end
  end

  def refresh_key_profile(socket, _token_ids), do: socket

  defp refresh_shards_among(socket, true), do: refresh_key_shards(socket)
  defp refresh_shards_among(socket, false), do: socket

  # The Key's holder opens its direct messages from here, and the holder of another
  # Key of the fleet writes to it; read again whenever the profile is.
  defp dms(%{issued?: true} = profile, actor),
    do: DmsLive.message_link(actor, profile.holder, profile.fleet_id, profile.token_id)

  defp dms(_profile, _actor), do: nil

  defp holder_moved?(%{issued?: false, token_id: token_id}, token_ids), do: token_id in token_ids

  defp holder_moved?(%{issued?: true, fleet_id: fleet_id, holder: holder}, token_ids),
    do: Profile.held_any?(fleet_id, holder, token_ids)

  # The next key on sale has no thread, so no one writes to it yet. A notice
  # about the last message sent goes once what the profile says about writing
  # has changed, which explains it.
  defp recheck_composer(%{assigns: %{key_profile: %{issued?: true} = profile}} = socket) do
    actor = ShellLive.human_actor(socket)

    socket =
      case Profile.composer(actor, profile.fleet_id) do
        composer when composer == profile.composer -> socket
        composer -> assign(socket, :key_profile, %{profile | composer: composer, notice: nil})
      end

    update(socket, :key_profile, &%{&1 | dms: dms(&1, actor)})
  end

  defp recheck_composer(socket), do: socket

  # Only the messages after the last one on show are read and added.
  defp show_key_activity(%{assigns: %{key_profile: profile}} = socket) do
    %{fleet_id: fleet_id, token_id: token_id} = profile
    messages = Profile.thread_after(fleet_id, token_id, profile.last_seq)

    socket
    |> assign(
      :key_profile,
      profile
      |> Map.merge(Profile.activity(fleet_id, token_id, profile.holder))
      |> Map.merge(%{
        last_seq: Profile.last_seq(messages, profile.last_seq),
        news: if(messages != [], do: "New message to Key #{Rules.grouped(token_id)}.")
      })
    )
    |> stream(:key_thread, Rooms.unmuted(messages, profile.muted), limit: -@key_thread_kept)
  end

  @doc """
  The open key's latest messages read again without the keys muted now, when
  the visitor's mutes in its fleet have changed.
  """
  def show_unmuted(
        %{assigns: %{key_profile: %{fleet_id: fleet_id, issued?: true} = shown}} = socket,
        fleet_id
      ) do
    muted = Rooms.muted_keys!(fleet_id, ShellLive.human_actor(socket))

    if muted == shown.muted do
      socket
    else
      messages = Profile.latest_thread(fleet_id, shown.token_id, shown.last_seq)

      socket
      |> assign(:key_profile, %{shown | muted: muted})
      |> stream(:key_thread, Rooms.unmuted(messages, muted),
        reset: true,
        limit: -@key_thread_kept
      )
    end
  end

  def show_unmuted(socket, _fleet_id), do: socket

  # The message is written straight to the key's thread, and the profile then
  # reads back what the thread holds after the last message it was showing.
  defp post_to_key(%{assigns: %{key_profile: %{issued?: true} = profile}} = socket, body) do
    %{fleet_id: fleet_id, token_id: token_id} = profile

    case Rooms.send_to_key(
           %{
             fleet_id: fleet_id,
             token_id: token_id,
             body: body,
             idempotency_key: profile.send_key
           },
           actor: ShellLive.human_actor(socket)
         ) do
      {:ok, _message} ->
        socket
        |> update(:key_profile, &%{&1 | draft: "", notice: nil, send_key: Ash.UUID.generate()})
        |> show_key_activity()
        |> update(:key_profile, &%{&1 | news: nil})

      {:error, refusal} ->
        socket
        |> update(
          :key_profile,
          &%{&1 | draft: body, notice: RoomsLive.post_refusal(refusal, fleet_id)}
        )
        |> recheck_composer()
    end
  end

  defp post_to_key(socket, _body), do: socket

  # The holder's own page drops the post at once; every other page with the
  # wall open hears of it (`Regents.Keyfleet.Rooms.WallRemoval`). A refusal says so
  # and leaves the post where it is.
  defp remove_from_wall(
         %{assigns: %{key_profile: %{issued?: true, fleet_id: fleet_id, token_id: token_id}}} =
           socket,
         message_id
       ) do
    case Rooms.remove_from_wall(fleet_id, token_id, message_id,
           actor: ShellLive.human_actor(socket)
         ) do
      {:ok, _removal} ->
        socket |> update(:key_profile, &%{&1 | notice: nil}) |> off_wall(message_id)

      {:error, _refusal} ->
        update(socket, :key_profile, &%{&1 | notice: @not_removed})
    end
  end

  defp remove_from_wall(socket, _message_id), do: socket

  defp off_wall(%{assigns: %{key_profile: profile}} = socket, message_id) do
    %{fleet_id: fleet_id, token_id: token_id, holder: holder} = profile

    socket
    |> assign(:key_profile, Map.merge(profile, Profile.activity(fleet_id, token_id, holder)))
    |> stream_delete_by_dom_id(:key_thread, "key-message-#{message_id}")
  end

  @doc "The open key's two vote figures, read again."
  def refresh_votes(%{assigns: %{key_profile: profile}} = socket) do
    votes = Profile.votes(profile.fleet_id, profile.token_id, profile.holder)
    assign(socket, :key_profile, Map.merge(profile, votes))
  end

  @doc "The open key's shards, read again."
  def refresh_key_shards(%{assigns: %{key_profile: %{issued?: true} = shown}} = socket),
    do:
      assign(socket, :key_profile, %{
        shown
        | shards: Profile.shards(shown.fleet_id, shown.token_id)
      })

  def refresh_key_shards(socket), do: socket

  # What the issued Key's agents' check-ins say comes from the readings every
  # page shares (`Regents.Keyfleet.Agents.Here`), heard from before it is read; a Key
  # not yet issued has no agents.
  defp follow_seen(%{assigns: %{key_profile: %{issued?: true} = profile}} = socket) do
    key = Here.lines_key(profile.fleet_id, profile.token_id)

    socket
    |> SharedFigures.follow(:key, [key])
    |> assign(:key_profile, Map.put(profile, :seen, seen(socket, profile.fleet_id, key)))
  end

  defp follow_seen(socket),
    do: socket |> SharedFigures.follow(:key, []) |> update(:key_profile, &Map.put(&1, :seen, %{}))

  # Each line as the reader's class reads it (`Here.seen_by/2`).
  defp seen(socket, fleet_id, key) do
    member? = ShellLive.member?(socket, fleet_id)

    Map.new(SharedFigures.reading(key) || [], fn {wallet, seen} ->
      {wallet, Here.seen_by(seen, member?)}
    end)
  end

  @doc "The open Key's agents' lights and lines, drawn again when their shared reading changes."
  def shared_changed(
        %{assigns: %{key_profile: %{issued?: true} = profile}} = socket,
        {:keyfleet_key_agents, _id} = key
      ) do
    if key == Here.lines_key(profile.fleet_id, profile.token_id),
      do: assign(socket, :key_profile, %{profile | seen: seen(socket, profile.fleet_id, key)}),
      else: socket
  end

  def shared_changed(socket, _key), do: socket

  @doc "The open Key's agents' lines, drawn again as the reader's new class reads them."
  def class_changed(
        %{assigns: %{key_profile: %{issued?: true, fleet_id: fleet_id} = profile}} = socket,
        fleet_id
      ),
      do: shared_changed(socket, Here.lines_key(fleet_id, profile.token_id))

  def class_changed(socket, _fleet_id), do: socket
end
