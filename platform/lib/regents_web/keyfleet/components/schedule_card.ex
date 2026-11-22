defmodule RegentsWeb.Keyfleet.Components.ScheduleCard do
  @moduledoc """
  Schedule, for a person whose paired agent has no scheduled check-in seen in
  a fleet where they hold a Key (`Regents.Keyfleet.Agents.Upkeep.unscheduled/2`): a
  sentence saying it isn't coming back on its own yet, Copy line with the
  guide's own words for scheduling check-ins, and who, with what their
  check-ins say (`Regents.Keyfleet.Agents.CheckInStatus`). It sits in the page and
  never covers it.

  A fleet's page shows it for that fleet at one height however many agents
  it names: the first, with how many more as a link to the Agents page, and
  Copy line beside them. The person may put it away there
  (`RegentsWeb.Keyfleet.Components.FleetPrompts`). On an Agents page (`page:
  :agents`) it shows for every fleet, always, naming each agent with its
  fleet, as Keyfleet's own Agents page showed it. It goes from both once a
  scheduled check-in is seen.
  """
  use RegentsWeb, :html

  alias Regents.Keyfleet.Fleets

  @check_in "Check in on Keyfleet as your keyfleet skill says."

  attr :id, :string, required: true

  attr :agents, :list,
    required: true,
    doc: "the agents with no scheduled check-in seen, as `Upkeep.unscheduled/2` gives them"

  attr :page, :atom,
    required: true,
    values: [:fleet, :agents],
    doc: "a fleet's page, which names the first agent and how many more, or the Agents page"

  attr :class, :any, default: nil
  attr :rest, :global
  slot :dismiss, doc: "a button that puts the card away"

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={["rg-panel", "schedule-card", "schedule-card--#{@page}", @class]}
      aria-labelledby={"#{@id}-title"}
      {@rest}
    >
      <div class="rg-panel__body">
        <header class="schedule-card__head">
          <h2 id={"#{@id}-title"}>Schedule</h2>
          {render_slot(@dismiss)}
        </header>
        <p class="schedule-card__words">{words(@agents)}</p>
        <div class="schedule-card__foot">
          <.who page={@page} agents={@agents} />
          <Regent.Primitives.copy_button id={"#{@id}-copy"} text={line()}>
            Copy line
          </Regent.Primitives.copy_button>
        </div>
      </div>
    </section>
    """
  end

  attr :page, :atom, required: true
  attr :agents, :list, required: true

  defp who(%{page: :fleet, agents: [first | more]} = assigns) do
    assigns = assign(assigns, first: first, more: length(more))

    ~H"""
    <p class="schedule-card__who" data-wallet={@first.wallet}>
      <strong class="schedule-card__name">{@first.name}</strong>
      <span class="check-in-status" data-light={@first.light}><span class="schedule-card__state">{@first.status}</span></span>
      <.link :if={@more > 0} class="schedule-card__more" navigate={~p"/account/agents"}>
        and {@more} more
      </.link>
    </p>
    """
  end

  defp who(%{page: :agents} = assigns) do
    ~H"""
    <ul class="schedule-card__agents">
      <li :for={agent <- @agents} data-wallet={agent.wallet} data-fleet={agent.fleet_id}>
        <strong class="schedule-card__name">{agent.name}</strong>
        <.link navigate={Fleets.path(agent.fleet_id)}>{Fleets.name(agent.fleet_id)}</.link>
        <span class="check-in-status" data-light={agent.light}>{agent.status}</span>
      </li>
    </ul>
    """
  end

  @doc """
  What the person gives their agent: the guide's own words for scheduling
  check-ins (`/keyfleet/skill.md`, Check-ins), which any agent paired here follows as
  pasted.
  """
  def line,
    do:
      "Schedule your Keyfleet check-ins, every 10 minutes to once a day, with your " <>
        "runtime's scheduler (#{RegentsWeb.Endpoint.url()}/keyfleet/agents says how), and " <>
        "start one now. Each starts fresh, told \"#{@check_in}\""

  @doc """
  The fleets whose Schedule this browser put away, from the cookie the
  `ScheduleCard` hook writes (`assets/js/keyfleet/hooks/schedule_card.ts`): their ids,
  joined by dots. Only the catalog's fleets are kept, each once.
  """
  def put_away(cookie) do
    catalog = Fleets.catalog_ids()
    cookie |> String.split(".", trim: true) |> Enum.filter(&(&1 in catalog)) |> Enum.uniq()
  end

  defp words(agents) do
    case Enum.uniq_by(agents, & &1.wallet) do
      [_one] ->
        "Your agent isn’t coming back on its own yet: give it this line to schedule its check-ins."

      _more ->
        "Your agents aren’t coming back on their own yet: give each this line to schedule its check-ins."
    end
  end
end
