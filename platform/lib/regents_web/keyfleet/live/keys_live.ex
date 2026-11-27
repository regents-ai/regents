defmodule RegentsWeb.Keyfleet.KeysLive do
  @moduledoc """
  One key's page: who owns it, whether it is present, the shards it has given
  out, whether its shards may vote, and whether a vote of the fleet has
  stopped it changing the workspace.

  Everything here is read from what the chain recorded, so a visitor sees the
  same standing the owner does; only the owner is offered the wallet buttons
  that issue, renew and end shards and turn agent voting on or off. A shard
  for each of the owner's paired agents is one press; any other wallet is
  typed under Other wallet. Anyone sees the key's presence, and its holder or
  a shard may mark it present.

  Someone holding a Key of the fleet is offered its messages: the Key's own
  holder opens its inbox, and the holder of another Key writes to it.
  """

  use RegentsWeb, :html

  import RegentsWeb.Keyfleet.Components.AgentPicture

  alias Regents.Account.Accounts
  alias Regents.Account.Actors.Human
  alias Regents.Account.Actors.System
  alias Regents.Account.PublicIdentity
  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Rules
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.Metadata
  alias Regents.Keyfleet.Keys.Profile
  alias RegentsWeb.Keyfleet.AgentGuides
  alias RegentsWeb.Keyfleet.Components.AgentSetup
  alias RegentsWeb.Keyfleet.Components.KeyCard
  alias RegentsWeb.Keyfleet.Components.PresenceCard
  alias RegentsWeb.Keyfleet.Components.Shell
  alias RegentsWeb.Keyfleet.DmsLive
  alias RegentsWeb.Keyfleet.ShellLive
  alias RegentsWeb.Keyfleet.WalletPanel

  @refreshing "Key ownership is being refreshed; try again in a moment."

  attr :key, :map, required: true
  attr :actor, :any, required: true, doc: "the signed-in person, or nil"
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"
  attr :client_tag, :string, required: true, doc: "the page's `client_tag`"

  def page(assigns) do
    ~H"""
    <article id="key-page" class="key-page">
      <header class="key-heading">
        <div class="key-heading__words">
          <%!-- Refreshing sits in the kicker's own line, so it never moves the panels below. --%>
          <p class="key-kicker">
            <.link patch={Fleets.path(@key.fleet_id)}>{@key.fleet_name}</.link><span
              :if={@key.refreshing?}
              id="key-refreshing"
            > · Refreshing…</span>
          </p>
          <h1 tabindex="-1">Key {Rules.grouped(@key.token_id)}</h1>
          <.link
            :if={@key.messages}
            id="key-messages"
            class="rg-button rg-button--primary key-messages"
            patch={@key.messages.path}
          >
            <span class="rg-button__label">{@key.messages.label}</span>
          </.link>
        </div>
        <KeyCard.card
          id="key-card"
          class="key-heading__card"
          src={@key.image}
          alt={"The card of Key #{Rules.grouped(@key.token_id)}"}
        />
      </header>

      <section :if={is_nil(@key.owner_wallet)} id="key-not-sold" class="key-panel">
        <h2>Unsold</h2>
        <p>Its holder and shards show up here once it’s sold.</p>
      </section>

      <div :if={@key.owner_wallet} class="key-grid">
        <p :if={@key.edits_restricted?} id="key-edits-restricted" class="key-notice">
          Edits restricted
          <Regent.Primitives.tip id="key-edits-tip" label="About restricted edits">
            A fleet vote paused workspace edits for this Key and its shards. Reading and chat stay open.
          </Regent.Primitives.tip>
        </p>

        <section class="key-panel" aria-labelledby="key-owner-title">
          <h2 id="key-owner-title">Holder</h2>
          <p class="key-wallet">
            <strong :if={@key.holder_name} id="key-owner-name">{@key.holder_name}</strong>
            <Regent.Primitives.address
              id="key-owner-address"
              address={@key.owner_wallet}
              label={@key.holder_ens}
            />
            <span :if={@key.owner?} id="key-owner-you" class="key-detail">You</span>
            <a
              id="key-owner-opensea"
              href={"https://opensea.io/#{@key.owner_wallet}"}
              rel="noopener noreferrer"
              target="_blank"
            >
              OpenSea
            </a>
          </p>
        </section>

        <PresenceCard.card
          :if={@key.deployed?}
          id="key-present"
          names_sender={false}
          can_mark?={@key.owner? or @key.shard_holder?}
          class="key-panel"
          fleet={@key.fleet}
          actor={@actor}
          lease={@lease}
          client_tag={@client_tag}
          token_id={@key.token_id}
        />

        <.live_component
          :if={@key.owner? and match?(%Human{}, @actor)}
          module={AgentSetup}
          id="key-agent-setup"
          class="key-panel"
          fleet_id={@key.fleet.fleet_id}
          actor={@actor}
        />

        <section id="key-shards" class="key-panel" aria-labelledby="key-shards-title">
          <h2 id="key-shards-title">
            Shards
            <Regent.Primitives.tip id="key-shards-tip" label="About shards">
              Delegated access for an agent wallet. Rewards still pay to you; shards end if the Key transfers.
            </Regent.Primitives.tip>
          </h2>

          <%!-- Only the holder can issue one, in the panel just below. --%>
          <Regent.Primitives.empty_state
            :if={@key.shards == [] and @key.owner?}
            id="key-no-shards"
            class="kf-empty"
            title="No shards yet."
          >
            Issue one below to let an agent act for this Key.
          </Regent.Primitives.empty_state>
          <Regent.Primitives.empty_state
            :if={@key.shards == [] and not @key.owner?}
            id="key-no-shards"
            class="kf-empty"
            title="No shards yet."
          />

          <.live_component
            :if={@key.owner? and @key.shards != []}
            module={WalletPanel}
            names_sender={false}
            id="key-shards-action"
            flow={:end_shard}
            fleet={@key.fleet}
            actor={@actor}
            lease={@lease}
            client_tag={@client_tag}
            token_id={@key.token_id}
            refresh={@key.shards}
          >
            <:buttons :let={panel}>
              <.shard_list shards={@key.shards} panel={panel} />
            </:buttons>
          </.live_component>

          <.shard_list :if={not @key.owner?} shards={@key.shards} panel={nil} />

          <Regent.Primitives.disclosure
            id="key-shard-rules"
            summary="Shard permissions"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <p>
              A shard lets an agent wallet chat, edit the workspace, mark this Key present, and claim
              rewards for up to 365 days. Enable Agent voting below to also let shards vote and
              propose. All payouts go to the Key holder, and every shard expires automatically if
              the Key changes hands.
            </p>
          </Regent.Primitives.disclosure>
        </section>

        <section
          :if={@key.owner?}
          id="key-issue-shard"
          class="key-panel"
          aria-labelledby="key-issue-shard-title"
        >
          <h2 id="key-issue-shard-title">
            New shard
            <Regent.Primitives.tip id="key-issue-tip" label="About issuing a shard">
              Grants a 30-day shard to that agent, signed in your wallet.
            </Regent.Primitives.tip>
          </h2>

          <ul :if={@key.agents != []} id="key-issue-agents" class="key-shard-list">
            <li :for={agent <- @key.agents} id={"key-issue-#{agent.wallet}"}>
              <div>
                <p class="key-name">{agent.name}</p>
                <span>{agent.runtime}</span>
              </div>
              <.live_component
                module={WalletPanel}
                names_sender={false}
                id={"key-issue-#{agent.wallet}-action"}
                class="key-issue-shard"
                flow={:issue_shard}
                fleet={@key.fleet}
                actor={@actor}
                lease={@lease}
                client_tag={@client_tag}
                inputs={%{"keys" => "#{@key.token_id}", "wallet" => agent.wallet, "days" => "30"}}
              >
                <:buttons :let={panel}>
                  <WalletPanel.step_button
                    panel={panel}
                    step="issue"
                    id={"key-issue-#{agent.wallet}-button"}
                  >
                    Issue shard
                  </WalletPanel.step_button>
                </:buttons>
              </.live_component>
            </li>
          </ul>

          <Shell.pair_button :if={@key.agents == []} id="key-issue-pair" />

          <Regent.Primitives.disclosure
            id="key-other-wallet"
            summary="Other wallet"
            class="key-other-wallet"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <.live_component
              module={WalletPanel}
              names_sender={false}
              id="key-issue-shard-action"
              class="key-issue-shard"
              flow={:issue_shard}
              fleet={@key.fleet}
              actor={@actor}
              lease={@lease}
              client_tag={@client_tag}
              inputs={%{"keys" => "#{@key.token_id}", "wallet" => "", "days" => "30"}}
            >
              <:fields :let={panel}>
                <div class="key-shard-form">
                  <.field
                    id="key-shard-wallet"
                    name="wallet"
                    label="Agent’s wallet"
                    value={panel.inputs["wallet"]}
                  />
                  <.field
                    id="key-shard-days"
                    name="days"
                    label="Days"
                    inputmode="numeric"
                    value={panel.inputs["days"]}
                  />
                </div>
              </:fields>
              <:buttons :let={panel}>
                <WalletPanel.step_button panel={panel} step="issue" id="key-issue-shard-button">
                  Issue shard
                </WalletPanel.step_button>
              </:buttons>
            </.live_component>
          </Regent.Primitives.disclosure>
        </section>

        <section
          :if={@key.owner?}
          id="key-agent-voting"
          class="key-panel"
          aria-labelledby="key-agent-voting-title"
        >
          <h2 id="key-agent-voting-title">
            Agent voting
            <Regent.Primitives.tip id="key-agent-voting-tip" label="About agent voting">
              Lets this Key’s shards vote and propose. The setting persists across new shards.
            </Regent.Primitives.tip>
          </h2>

          <.live_component
            module={WalletPanel}
            names_sender={false}
            id="key-agent-voting-action"
            flow={:agent_voting}
            fleet={@key.fleet}
            actor={@actor}
            lease={@lease}
            client_tag={@client_tag}
            refresh={@key.shards}
            inputs={%{"keys" => "#{@key.token_id}"}}
          >
            <:fields :let={panel}>
              <div class="key-shard-form">
                <.field
                  id="key-agent-voting-keys"
                  name="keys"
                  label="Keys"
                  value={panel.inputs["keys"]}
                />
              </div>
            </:fields>
            <:notes :let={panel}>
              <p :if={voting(panel)} id="key-agent-voting-state" class="key-detail">
                On for {voting(panel)}
              </p>
            </:notes>
            <:buttons :let={panel}>
              <WalletPanel.step_button panel={panel} step="on" id="key-agent-voting-on">
                Turn on
              </WalletPanel.step_button>
              <WalletPanel.step_button
                panel={panel}
                step="off"
                id="key-agent-voting-off"
                variant="secondary"
              >
                Turn off
              </WalletPanel.step_button>
            </:buttons>
          </.live_component>
        </section>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :inputmode, :string, default: nil

  # A field the wallet buttons' steps are built from, as long as its box.
  defp field(assigns) do
    ~H"""
    <Regent.Primitives.field :let={field} id={@id} label={@label}>
      <input
        id={field.id}
        name={@name}
        value={@value}
        inputmode={@inputmode}
        maxlength={WalletPanel.box(@name)}
        autocomplete="off"
        aria-describedby={field.described_by}
        data-onchain-input={@name}
      />
    </Regent.Primitives.field>
    """
  end

  # The keys named whose shards may vote now, or nil for none.
  defp voting(panel) do
    case WalletPanel.figures(panel) do
      %{voting: [_key | _more] = keys} -> Enum.map_join(keys, ", ", &"Key #{Rules.grouped(&1)}")
      _none -> nil
    end
  end

  attr :shards, :list, required: true
  attr :panel, :any, required: true, doc: "the end and renew buttons' panel, nil for a visitor"

  # Each shard: its agent, or its wallet while no agent has signed in with it,
  # when it runs out, and for the owner the buttons that end or renew it.
  defp shard_list(assigns) do
    ~H"""
    <ul :if={@shards != []} class="key-shard-list">
      <li :for={shard <- @shards} id={"key-shard-#{shard.wallet}"}>
        <div>
          <p :if={shard.agent} class="key-name">
            <.agent_picture src={shard.agent.avatar_src} />
            {shard.agent.name}
          </p>
          <p :if={is_nil(shard.agent)} class="key-name">No agent yet</p>
          <span :if={shard.agent}>{AgentGuides.runtime(shard.agent.harness)}</span>
          <span>Until {date(shard.expires_at)}</span>
          <Regent.Primitives.address id={"key-shard-address-#{shard.wallet}"} address={shard.wallet} />
        </div>

        <div :if={@panel} class="key-shard-actions">
          <WalletPanel.step_button
            panel={@panel}
            step={"renew-#{shard.wallet}"}
            id={"key-shard-renew-#{shard.wallet}"}
          >
            Renew 30 days
          </WalletPanel.step_button>
          <WalletPanel.step_button
            panel={@panel}
            step={"end-#{shard.wallet}"}
            id={"key-shard-end-#{shard.wallet}"}
            variant="secondary"
          >
            End
          </WalletPanel.step_button>
        </div>
      </li>
    </ul>
    """
  end

  defp date(datetime), do: Calendar.strftime(datetime, "%-d %B %Y")

  @doc """
  What someone is told when a change waits on the fleet's key ownership being
  read again from the chain.
  """
  def refreshing, do: @refreshing

  @doc """
  What the key's page shows of the key, as the visitor may see it, and for its
  holder the paired agents with no shard of it yet, each given one in a press
  (`agents`). An agent that holds a shard renews it in the Shards list.
  """
  def key_view(socket, fleet_id, token_id) do
    actor = ShellLive.human_actor(socket)
    key = Keys.current_key!(fleet_id, token_id, actor: actor, load: [:fleet])
    {holder_name, holder_ens} = PublicIdentity.holder(holder(key))
    owner? = owns_key?(actor, key)
    shards = if(key, do: Profile.shards(fleet_id, token_id), else: [])

    %{
      fleet_id: fleet_id,
      token_id: token_id,
      fleet_name: Fleets.name(fleet_id),
      fleet: key && %{fleet_id: fleet_id, chain_id: key.fleet.chain_id},
      deployed?: key != nil and key.fleet.manager_address != nil,
      owner_wallet: key && key.owner_wallet,
      holder_name: holder_name,
      holder_ens: holder_ens,
      image: if(key, do: Metadata.image(key.fleet, token_id), else: Metadata.pass()),
      owner?: owner?,
      shard_holder?: holds_shard?(actor, shards),
      refreshing?: not Chain.fresh?(fleet_id),
      edits_restricted?:
        match?([%{restricted: true}], Keys.latest_edits_restrictions!(fleet_id, [token_id])),
      shards: shards,
      messages: DmsLive.message_link(actor, key && key.owner_wallet, fleet_id, token_id),
      agents: if(owner?, do: unsharded(actor, shards), else: [])
    }
  end

  defp unsharded(actor, shards) do
    sharded = MapSet.new(shards, & &1.wallet)

    for agent <- Agents.my_agents(actor),
        agent.wallet not in sharded,
        do: %{
          wallet: agent.wallet,
          name: agent.name,
          runtime: RegentAgents.Harness.label(agent.harness)
        }
  end

  @doc "The key on show read again when it is among the fleet's changed keys."
  def refresh_key(
        %{assigns: %{key: %{fleet_id: fleet_id, token_id: token_id}}} = socket,
        fleet_id,
        token_ids
      ) do
    if token_id in token_ids,
      do: assign(socket, :key, key_view(socket, fleet_id, token_id)),
      else: socket
  end

  def refresh_key(socket, _fleet_id, _token_ids), do: socket

  @doc "The holder's own Key on show read again when their paired agents change."
  def agents_changed(%{assigns: %{key: %{owner?: true} = key}} = socket),
    do: assign(socket, :key, key_view(socket, key.fleet_id, key.token_id))

  def agents_changed(socket), do: socket

  # The account linking the key's wallet, named as the Member List names it.
  defp holder(nil), do: nil

  defp holder(key) do
    case Keys.holder_account_id(key.owner_wallet) do
      nil ->
        nil

      account_id ->
        [account] =
          Accounts.accounts_by_ids!([account_id],
            actor: %System{},
            query: [select: [:wallet_address]],
            load: [:display_name, :ens_name]
          )

        account
    end
  end

  defp owns_key?(%Human{wallet_addresses: wallets}, %{owner_wallet: owner}),
    do: owner in wallets

  defp owns_key?(_actor, _key), do: false

  defp holds_shard?(%Human{wallet_addresses: wallets}, shards),
    do: Enum.any?(shards, &(&1.wallet in wallets))

  defp holds_shard?(_actor, _shards), do: false
end
