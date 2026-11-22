defmodule RegentsWeb.Keyfleet.Components.AgentSetup do
  @moduledoc """
  The agents a signed-in person has paired, each with the states its setup ends
  in as dots, the ones its doctor names as steps (`Regents.Keyfleet.Agents.Upkeep`): an
  agent with no Key or shard to mark has no gas or marked dot, and a quiet line
  instead saying a shard is optional. A line also shows when its scheduled run
  has stopped. It takes
  no room for a person with no agent. Each dot opens a few words saying what it
  is and, when it is not done, how to put it right. The states come from the
  chain reader's records and check-ins (`Regents.Keyfleet.Agents.Upkeep`); only gas asks
  the chain, so the row is drawn at once and that dot fills in when the answer
  comes. The page sends `changed: true` when the person's agents change (a
  pairing, a check-in) or Keys are marked present, and the agents are read
  again; gas is asked again only when an agent or the number of Keys it acts
  for has changed, since nothing else moves it.
  """
  use RegentsWeb, :live_component

  alias Phoenix.LiveView.AsyncResult
  alias Regents.Keyfleet.Agents.Upkeep

  @impl true
  def mount(socket), do: {:ok, assign(socket, class: nil, gas: AsyncResult.loading())}

  @impl true
  def update(
        %{changed: true},
        %{assigns: %{actor: actor, fleet_id: fleet_id, agents: shown}} = socket
      ) do
    agents = Upkeep.person_agents(actor, fleet_id)
    socket = assign(socket, agents: agents)
    {:ok, if(gas_asked(agents) == gas_asked(shown), do: socket, else: ask_gas(socket))}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(changed?(socket, :fleet_id), do: read(socket), else: socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      class={["agent-setup", @class]}
      aria-labelledby={"#{@id}-title"}
      hidden={@agents == []}
    >
      <h2 id={"#{@id}-title"}>Your agent</h2>
      <div
        :for={{agent, n} <- Enum.with_index(@agents)}
        class="agent-setup__agent"
        data-wallet={agent.wallet}
      >
        <span class="agent-setup__name">{agent.name}</span>
        <ul class="agent-setup__states">
          <li :for={{label, state, words} <- states(agent, @gas)} data-state={word(state)}>
            <Regent.Primitives.tip id={"#{@id}-#{n}-#{String.downcase(label)}"}>
              <:figure>
                <span class="agent-setup__dot" aria-hidden="true"></span>
                <span class="visually-hidden">{label}: {word(state)}</span>
              </:figure>
              <strong>{label}.</strong> {words}
            </Regent.Primitives.tip>
          </li>
        </ul>
        <p :if={:marked not in agent.steps} class="agent-setup__tip">
          Optional: give it a shard of your Key and it marks your Keys present for you.
        </p>
        <p :if={agent.run_missed} class="agent-setup__wrong">{missed(agent.lapses_at)}</p>
      </div>
    </section>
    """
  end

  defp read(%{assigns: %{actor: actor, fleet_id: fleet_id}} = socket),
    do: socket |> assign(agents: Upkeep.person_agents(actor, fleet_id)) |> ask_gas()

  defp ask_gas(%{assigns: %{agents: agents}} = socket) do
    assign_async(socket, :gas, fn ->
      {:ok, %{gas: Map.new(agents, &{&1.wallet, Upkeep.pays?(&1.wallet, &1.key_count)})}}
    end)
  end

  # What gas is asked for: each agent's wallet and how many Keys it marks.
  defp gas_asked(agents), do: Enum.map(agents, &{&1.wallet, &1.key_count})

  # Each of the agent's steps (`Regents.Keyfleet.Agents.Upkeep`) with the words its
  # dot opens: what it is, and how to put it right when it is not done.
  defp states(agent, %AsyncResult{} = gas), do: Enum.map(agent.steps, &state(&1, agent, gas))

  defp state(:paired, _agent, _gas),
    do: {"Paired", true, "This agent is paired with your account."}

  defp state(:gas, agent, gas) do
    paid = gas.result && gas.result[agent.wallet]
    {"Gas", paid, gas_words(paid, gas.loading)}
  end

  defp state(:schedule, agent, _gas),
    do: {"Schedule", agent.schedule, schedule_words(agent.schedule)}

  defp state(:marked, agent, _gas), do: {"Marked", agent.marked, marked_words(agent.marked)}

  defp state(:repeated, agent, _gas),
    do: {"Repeated", agent.repeated, repeated_words(agent.repeated)}

  defp gas_words(true, _loading), do: "Its wallet has the ETH on Base to mark your Keys."
  defp gas_words(false, _loading), do: "Its wallet is out of ETH. Send it ETH on Base."

  defp gas_words(nil, loading) when loading in [nil, false],
    do: "The chain didn’t answer. Reload in a minute."

  defp gas_words(nil, _loading), do: "Reading its wallet."

  defp schedule_words(true), do: "Its daily run is scheduled."
  defp schedule_words(false), do: "No daily run yet. Ask your agent to schedule one."

  # Marked, as `Regents.Keyfleet.Agents.Upkeep` reads it, is also true for a Key that
  # waits for its automatic start, which counts in votes only once it comes.
  defp marked_words(true),
    do: "Every Key it can mark is present, or waits for its automatic start."

  defp marked_words(false),
    do: "A Key it can mark isn’t present. Ask your agent to mark it, or mark it yourself."

  defp repeated_words(true), do: "Its daily run keeps arriving on time."

  defp repeated_words(false),
    do: "Its daily run hasn’t come back on time yet. Check after its next run."

  defp word(true), do: "yes"
  defp word(false), do: "no"
  defp word(nil), do: "unknown"

  defp missed(nil), do: "Run missed. Keys lapsed."

  defp missed(lapses_at) do
    if DateTime.after?(lapses_at, DateTime.utc_now()),
      do: "Run missed. Keys lapse #{Calendar.strftime(lapses_at, "%-d %b")}.",
      else: "Run missed. Keys lapsed."
  end
end
