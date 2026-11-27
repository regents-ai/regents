defmodule RegentsWeb.Keyfleet.Components.FleetPrompts do
  @moduledoc """
  The two buttons at the top of a fleet's page for a signed-in person who
  holds a Key in it, side by side when both apply, each only while it has
  something to do.

  Pair shows while the person has no agent paired, and opens the site's Pair
  New Agent page (`/pair`), whose message sends the agent to this fleet once
  paired. Mark present shows while some of the person's Keys are
  idle, by the rule the page's presence marks read (the `idle` calculation of
  `Regents.Keyfleet.Keys.KeyAttachment`), with how many beside it. One press marks
  every idle Key the sending wallet holds present
  (`Regents.Keyfleet.WalletSteps` flow `:present_idle`).

  Under them, Schedule (`RegentsWeb.Keyfleet.Components.ScheduleCard`) shows while an
  agent the person paired has no scheduled check-in seen here. Its person may
  put it away for this fleet, which only their browser remembers, in a cookie
  the `ScheduleCard` hook writes. The page passes `schedule_put_away?`, read
  from that cookie as the page was requested and kept as the hook says, so a
  card shows from the first paint or not at all and never moves the page
  once drawn.

  The page sends `changed: true` when the person's agents, the fleet's Keys or
  a step sent from the page change, and all three are read again. It sends
  `present: token_ids` when Keys of the fleet are marked present, and they are
  read again only when one of them was the person's idle Key.
  """
  use RegentsWeb, :live_component

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Agents.Upkeep
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Keys
  alias RegentsWeb.Keyfleet.Components.Count
  alias RegentsWeb.Keyfleet.Components.ScheduleCard
  alias RegentsWeb.Keyfleet.WalletPanel

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, pair?: false, idle: [], schedule: [])}

  @impl true
  def update(%{changed: true}, socket), do: {:ok, read(socket)}

  def update(%{present: token_ids}, socket) do
    ours? = Enum.any?(socket.assigns.idle, &(&1 in token_ids))
    {:ok, if(ours?, do: read(socket), else: socket)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    moved? = changed?(socket, :fleet) or changed?(socket, :actor)
    {:ok, if(moved?, do: read(socket), else: socket)}
  end

  # Pairing without a Key opens nothing here, so a person holding none sees
  # none of the three.
  defp read(%{assigns: %{actor: %Human{} = actor, fleet: %{fleet_id: fleet_id}}} = socket) do
    keys = Keys.keys_held_in_fleet!(fleet_id, actor.wallet_addresses, actor: actor, load: [:idle])

    assign(socket,
      pair?: keys != [] and not Agents.has_paired_agent?(actor),
      idle: for(%{idle: true, token_id: token_id} <- keys, do: token_id),
      schedule: if(keys == [], do: [], else: Upkeep.unscheduled(actor, [fleet_id]))
    )
  end

  defp read(socket), do: assign(socket, pair?: false, idle: [], schedule: [])

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="fleet-prompts">
      <div :if={@pair? or @idle != []} class="fleet-prompts__row">
        <.link
          :if={@pair?}
          id={"#{@id}-pair"}
          href={~p"/pair?#{[to: Fleets.path(@fleet.fleet_id)]}"}
          class="rg-button rg-button--primary fleet-prompts__pair"
        >
          <span class="rg-button__label">Pair agent</span>
        </.link>
        <.live_component
          :if={@idle != []}
          module={WalletPanel}
          id={"#{@id}-present"}
          class="fleet-prompts__present"
          flow={:present_idle}
          fleet={@fleet}
          actor={@actor}
          lease={@lease}
          client_tag={@client_tag}
          names_sender={false}
          refresh={@idle}
        >
          <:buttons :let={panel}>
            <WalletPanel.step_button
              panel={panel}
              step="present"
              id={"#{@id}-mark"}
              variant={if @pair?, do: "secondary", else: "primary"}
            >
              Mark present
            </WalletPanel.step_button>
            <span class="fleet-prompts__idle">
              <Count.count id={"#{@id}-idle"} value={length(@idle)} one="Key idle" many="Keys idle" />
            </span>
          </:buttons>
        </.live_component>
      </div>
      <ScheduleCard.card
        :if={@schedule != [] and not @schedule_put_away?}
        id={"#{@id}-schedule"}
        class="fleet-prompts__schedule"
        agents={@schedule}
        page={:fleet}
        phx-hook="ScheduleCard"
        phx-mounted={JS.ignore_attributes(["hidden"])}
        data-fleet={@fleet.fleet_id}
      >
        <:dismiss>
          <button type="button" class="schedule-card__dismiss" aria-label="Dismiss" data-dismiss>
            <Regent.Icons.icon name="x" />
          </button>
        </:dismiss>
      </ScheduleCard.card>
    </div>
    """
  end
end
