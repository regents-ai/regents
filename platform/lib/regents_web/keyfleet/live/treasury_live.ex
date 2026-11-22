defmodule RegentsWeb.Keyfleet.TreasuryLive do
  @moduledoc """
  Public treasury balances, wallet actions, history, permissions and contracts.
  Uses the existing indexed reads and wallet approval flow.
  """

  use RegentsWeb, :html

  import Regents.Keyfleet.Fleets.Rules, only: [grouped: 1]
  import RegentsWeb.Keyfleet.Components.LoadFailed

  alias Regents.Keyfleet.Authority
  alias Regents.Keyfleet.Fleets.Rules
  alias RegentsWeb.Keyfleet.ProposalsLive
  alias RegentsWeb.Keyfleet.ProposalsPage
  alias RegentsWeb.Keyfleet.WalletPanel

  attr :page, :any, required: true, doc: "the Treasury page as read, or `:unreadable`"
  attr :actor, :any, required: true, doc: "the signed-in person, or nil"
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"
  attr :reread, :integer, required: true, doc: "counts the times its figures were asked for again"
  attr :resting?, :boolean, required: true, doc: "whether its refresh waits to be pressed again"

  # Drawn inside the fleet's page, under its name and bar (`RegentsWeb.Keyfleet.FleetLive`).
  def page(%{page: :unreadable} = assigns) do
    ~H"""
    <article id="treasury-page" class="proposals-page">
      <section id="treasury-unreadable" class="proposals-panel">
        <.load_failed />
      </section>
    </article>
    """
  end

  def page(%{page: %{fleet_name: nil}} = assigns),
    do: ~H|<ProposalsLive.missing_fleet id="treasury-page" />|

  def page(assigns) do
    ~H"""
    <article id="treasury-page" class="proposals-page">
      <p
        :if={@page.catching_up?}
        id="treasury-catching-up"
        class="proposals-notice"
        role="status"
      >
        Treasury figures are catching up. Check the timestamp below before acting.
      </p>

      <ProposalsLive.treasury
        :if={@page.treasury}
        treasury={@page.treasury}
        page={@page}
        actor={@actor}
        lease={@lease}
        reread={@reread}
        resting?={@resting?}
      />

      <%!-- A fleet not yet on chain has no treasury to show. --%>
      <section :if={!@page.treasury} id="treasury-not-live" class="proposals-panel">
        <Regent.Primitives.empty_state
          class="kf-empty"
          title="This fleet’s treasury opens once the fleet is live."
        >
          <:action>
            <.link
              class="rg-button rg-button--secondary"
              patch={Regents.Keyfleet.Fleets.path(@page.fleet_id)}
            >
              <span class="rg-button__label">Back to the fleet</span>
            </.link>
          </:action>
        </Regent.Primitives.empty_state>
      </section>

      <section
        :if={@page.carried != [] or @page.treasury}
        id="treasury-carried"
        class="proposals-panel"
        aria-labelledby="treasury-carried-title"
      >
        <h2 id="treasury-carried-title">Executed votes</h2>
        <Regent.Primitives.empty_state
          :if={@page.carried == []}
          id="treasury-carried-empty"
          class="kf-empty"
          title="No votes have been carried out yet."
        >
          <:action>
            <.link
              class="rg-button rg-button--secondary"
              patch={ProposalsPage.list_path(@page.fleet_id)}
            >
              <span class="rg-button__label">See proposals</span>
            </.link>
          </:action>
        </Regent.Primitives.empty_state>
        <ol :if={@page.carried != []} id="treasury-carried-list" class="proposals-lines">
          <li :for={proposal <- @page.carried} data-proposal={proposal.number}>
            <.link patch={ProposalsPage.detail_path(@page.fleet_id, proposal.number)}>
              Proposal {proposal.number}
            </.link>
            <span :if={proposal.text} class="proposals-words proposals-words--short">
              {proposal.text}
            </span>
          </li>
        </ol>
      </section>

      <.usage :if={@page.usage} usage={@page.usage} />

      <section id="treasury-rules" class="proposals-panel" aria-labelledby="treasury-rules-title">
        <h2 id="treasury-rules-title">Contracts</h2>
        <div :if={@page.manager_address} class="proposals-address">
          <span>Manager</span>
          <Regent.Primitives.address id="fleet-manager" address={@page.manager_address} />
        </div>
        <Regent.Primitives.disclosure id="treasury-permissions-more" summary="Permissions">
          <dl class="treasury-permissions">
            <div :for={row <- Authority.treasury_rows()}>
              <dt>{row.what}</dt>
              <dd>{row.who}<span class="proposals-detail">{Authority.needs(row)}</span></dd>
            </div>
          </dl>
        </Regent.Primitives.disclosure>
        <Regent.Primitives.disclosure
          id="treasury-fleet-details"
          summary="Fleet details"
        >
          <p>{Rules.pricing(@page.fleet_id)}</p>
          <.progress :if={@page.deployed?} page={@page} />
          <.launch_upkeep :if={@page.deployed?} page={@page} actor={@actor} lease={@lease} />
        </Regent.Primitives.disclosure>
      </section>
    </article>
    """
  end

  attr :usage, :map, required: true, doc: "the figures of the fleet's usage this month"

  # What the fleet has used of the site this month, as last counted: how large
  # its workspace is, what its chat has taken and, once its hub is read, how
  # long its notebook machines ran. It only measures.
  defp usage(assigns) do
    ~H"""
    <section id="treasury-usage" class="proposals-panel" aria-labelledby="treasury-usage-title">
      <h2 id="treasury-usage-title">Usage</h2>
      <dl class="proposals-facts treasury-usage">
        <div>
          <dt>Workspace</dt>
          <dd>
            <Regent.Primitives.figure
              id="treasury-usage-workspace"
              value={size(@usage.workspace_bytes)}
            />
            <span id="treasury-usage-items" class="proposals-detail">
              {counted(@usage.workspace_items, "item")}
            </span>
          </dd>
        </div>
        <div>
          <dt>Chat</dt>
          <dd>
            <Regent.Primitives.figure id="treasury-usage-chat" value={size(@usage.chat_bytes)} />
            <span id="treasury-usage-posts" class="proposals-detail">
              {counted(@usage.chat_posts, "post")}
            </span>
          </dd>
        </div>
        <div :if={@usage.notebook_seconds}>
          <dt>Notebooks</dt>
          <dd>
            <Regent.Primitives.figure
              id="treasury-usage-notebooks"
              value={hours(@usage.notebook_seconds)}
            />
          </dd>
        </div>
      </dl>
      <p class="proposals-detail">
        {Calendar.strftime(@usage.month, "%B %Y")} so far, counted every hour.
      </p>
    </section>
    """
  end

  @kb 1024
  @mb 1024 * 1024
  @gb 1024 * 1024 * 1024

  # A size the way a person reads it.
  defp size(bytes) when bytes < @kb, do: "#{bytes} B"
  defp size(bytes) when bytes < @mb, do: "#{Float.round(bytes / @kb, 1)} KB"
  defp size(bytes) when bytes < @gb, do: "#{Float.round(bytes / @mb, 1)} MB"
  defp size(bytes), do: "#{Float.round(bytes / @gb, 1)} GB"

  defp counted(1, word), do: "1 #{word}"
  defp counted(count, word), do: "#{grouped(count)} #{word}s"

  # Machine time to the tenth of an hour.
  defp hours(seconds) do
    tenths = round(seconds / 360)
    whole = grouped(div(tenths, 10))

    case rem(tenths, 10) do
      0 when tenths == 10 -> "1 hour"
      0 -> "#{whole} hours"
      tenth -> "#{whole}.#{tenth} hours"
    end
  end

  attr :page, :map, required: true

  # The fleet's sales so far.
  defp progress(assigns) do
    ~H"""
    <h3 id="fleet-progress-title">Progress</h3>
    <p :if={@page.catching_up?} class="proposals-detail">Figures are catching up.</p>
    <dl :if={not @page.catching_up?} class="proposals-facts">
      <div>
        <dt>Keys issued</dt>
        <dd :if={@page.progress.max_supply}>
          {grouped(@page.progress.total_minted)} of {grouped(@page.progress.max_supply)}
        </dd>
        <dd :if={is_nil(@page.progress.max_supply)}>
          {grouped(@page.progress.total_minted)}
        </dd>
      </div>
      <div :if={@page.progress.completed_levels}>
        <dt>Levels complete</dt>
        <dd>{@page.progress.completed_levels}</dd>
      </div>
    </dl>
    <p
      :if={not @page.catching_up? and is_nil(@page.progress.max_supply)}
      id="fleet-levels-keep-opening"
      class="proposals-detail"
    >
      New levels keep opening.
    </p>
    <p
      :if={not @page.catching_up? and is_nil(@page.progress.next_price)}
      class="proposals-detail"
    >
      Every Key has been issued.
    </p>
    """
  end

  attr :page, :map, required: true
  attr :actor, :any, required: true
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"

  # The fleet's token launch, once an approved proposal has made one: four
  # buttons anyone may press to settle its sale, add its token to the daily
  # split, release the tokens set aside for the treasury and collect the
  # pool's fees.
  defp launch_upkeep(assigns) do
    ~H"""
    <section id="fleet-launch" aria-labelledby="fleet-launch-title">
      <h3 id="fleet-launch-title">
        Token launch
        <Regent.Primitives.tip id="fleet-launch-tip" label="About the token launch">
          A launch the fleet voted for sells its token through Autolaunch. Once the sale ends, anyone can settle it, add the token to the Daily Treasury Slice to Keys, release the tokens set aside for the treasury, and collect the pool’s fees for it.
        </Regent.Primitives.tip>
      </h3>
      <.live_component
        module={WalletPanel}
        id="fleet-launch-action"
        flow={:launch_upkeep}
        fleet={%{fleet_id: @page.fleet_id, chain_id: @page.chain_id}}
        actor={@actor}
        lease={@lease}
      >
        <:notes :let={panel}>
          <dl
            :if={is_nil(@actor) and launched?(panel)}
            id="fleet-launch-facts"
            class="proposals-facts"
          >
            <div>
              <dt>Token</dt>
              <dd>
                <Regent.Primitives.address
                  id="fleet-launch-token"
                  address={WalletPanel.figures(panel).token}
                />
              </dd>
            </div>
            <div>
              <dt>Sale</dt>
              <dd id="fleet-launch-sale">{sale(panel)}</dd>
            </div>
            <div>
              <dt>Daily Treasury Slice to Keys</dt>
              <dd id="fleet-launch-split">
                {if WalletPanel.figures(panel).bound?, do: "Included", else: "Not yet"}
              </dd>
            </div>
          </dl>
        </:notes>
        <:buttons :let={panel}>
          <WalletPanel.step_button
            :if={launched?(panel)}
            panel={panel}
            step="settle"
            id="fleet-launch-settle"
          >
            Settle sale
          </WalletPanel.step_button>
          <WalletPanel.step_button
            :if={launched?(panel)}
            panel={panel}
            step="bind"
            id="fleet-launch-bind"
          >
            Add to slice
          </WalletPanel.step_button>
          <WalletPanel.step_button
            :if={launched?(panel)}
            panel={panel}
            step="release"
            id="fleet-launch-release"
          >
            Release tokens
          </WalletPanel.step_button>
          <WalletPanel.step_button
            :if={launched?(panel)}
            panel={panel}
            step="collect"
            id="fleet-launch-collect"
          >
            Collect fees
          </WalletPanel.step_button>
        </:buttons>
      </.live_component>
    </section>
    """
  end

  # Until an approved proposal has made a launch, there is nothing to upkeep.
  defp launched?(panel), do: WalletPanel.figures(panel)[:launch_id] != nil

  # Where the launch's sale stands, for a visitor, who sees no buttons.
  defp sale(panel) do
    case WalletPanel.figures(panel) do
      %{lifecycle: :active, blocked: %{"settle" => :sale_running}} -> "On sale"
      %{lifecycle: :active} -> "Ended, ready to settle"
      %{lifecycle: :graduated} -> "Sold"
      %{lifecycle: :failed} -> "Didn’t sell"
      %{lifecycle: :none} -> "Not started"
    end
  end
end
