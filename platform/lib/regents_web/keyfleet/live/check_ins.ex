defmodule RegentsWeb.Keyfleet.CheckIns do
  @moduledoc """
  What agents' check-ins with a fleet say, as people see it: one agent's
  status line, and the fleet's "Here now" listing the agents holding
  shards of its keys.

  A status comes only from when the agent's check-ins arrived
  (`Regents.Keyfleet.Agents.CheckInStatus`), never from what it says about itself.
  """

  use RegentsWeb, :html

  import Regents.Keyfleet.Fleets.Rules, only: [grouped: 1]
  import RegentsWeb.Keyfleet.Components.AgentPicture

  alias Regents.Keyfleet.Agents.Avatar

  attr :seen, :map,
    default: nil,
    doc:
      "what the agent's check-ins say (`Regents.Keyfleet.Agents.Here`): its light, the light's " <>
        "meaning, and a line of when it was last seen and last posted or worked"

  attr :class, :string, default: nil
  attr :rest, :global

  @doc """
  One agent's check-in light and when it was last seen, as every page shares
  them (`Regents.Keyfleet.Agents.Here`). The light's meaning shows on hover and is read
  out before the line. Before its first reading the line keeps its place,
  empty.
  """
  def status(assigns) do
    ~H"""
    <span
      class={["check-in-status", @class]}
      data-light={@seen && @seen.light}
      title={@seen && @seen.label}
      {@rest}
    >
      <span :if={@seen} class="visually-hidden">{@seen.label}.</span>
      {@seen && @seen.line}
    </span>
    """
  end

  attr :agents, :any,
    required: true,
    doc: "the agents shown, a stream of `Regents.Keyfleet.Agents.Here`'s reading"

  attr :shown, :integer, required: true, doc: "how many agents the stream shows"

  attr :agents_here, :integer,
    required: true,
    doc: "how many agents are here, or nil when they couldn't be counted"

  @doc """
  The fleet's "Here now", in the hall's right-hand column: the agents here,
  the most recently seen first, each with the key it acts as and its
  check-in light.
  """
  def who_is_here(assigns) do
    ~H"""
    <section id="fleet-who" class="who-is-here" aria-labelledby="fleet-who-title">
      <h2 id="fleet-who-title">Here now</h2>

      <Regent.Primitives.empty_state
        :if={@shown == 0 and @agents_here != nil}
        id="fleet-who-empty"
        class="kf-empty"
        title="No agents here yet."
      />
      <%!-- Uncounted is never told as nobody, the way the fleet's bar tells it. --%>
      <p
        :if={@shown == 0 and is_nil(@agents_here)}
        id="fleet-who-uncounted"
        class="who-is-here__note"
      >
        We couldn’t check who’s here just now.
      </p>

      <ul id="fleet-who-list" class="who-is-here__list" phx-update="stream" hidden={@shown == 0}>
        <li :for={{dom_id, agent} <- @agents} id={dom_id}>
          <p class="who-is-here__name">
            <.agent_picture src={Avatar.shown(agent.avatar_url, agent.wallet_address)} />
            <strong>{agent.name}</strong>
            <span class="who-is-here__keys">Key {grouped(agent.key)}</span>
          </p>
          <.status seen={agent.seen} class="who-is-here__status" />
        </li>
      </ul>

      <p :if={@agents_here && @agents_here > @shown} class="who-is-here__note">
        {grouped(@agents_here)} agents are here. These are the {@shown} that checked in most recently.
      </p>
    </section>
    """
  end
end
