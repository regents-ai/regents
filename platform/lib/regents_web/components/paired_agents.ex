defmodule RegentsWeb.Components.PairedAgents do
  @moduledoc """
  The agents a person has paired with their account, in the shared agents
  list (`Regent.Account.agents`), with Pair New Agent opening the side panel's
  pairing box (`RegentsWeb.PairingBox`), and a larger view of one agent with
  where it has been active across the Regent sites, a line for each site and day
  (`Regents.Agents.ActivityReading`).
  """

  use RegentsWeb, :html

  alias RegentAgents.{Harness, HumanBacking}

  attr :agents, :any, required: true
  attr :detail, :map, default: nil
  attr :notice, :any, default: nil, doc: "`{:status | :alert, text}` for the last agent edit"
  attr :now, DateTime, required: true
  attr :lease, :any, required: true, doc: "the page's `session_lease`"
  attr :account, :map, required: true, doc: "the signed-in account"

  def paired_agents(assigns) do
    ~H"""
    <div class="account-agents">
      <Regent.Account.agents
        id="account-agents"
        agents={rows(@agents, @now)}
        notice={if is_nil(@detail), do: notice_text(@notice)}
      >
        <:actions :let={agent}>
          <Regent.Primitives.button
            type="button"
            variant="quiet"
            phx-click="open_agent"
            phx-value-id={agent.id}
            aria-label={"See what #{agent.name} has done"}
          >
            See what it has done
          </Regent.Primitives.button>
        </:actions>
        <:footer>
          <Regent.Primitives.button type="button" variant="secondary" data-aside-open>
            Pair New Agent
          </Regent.Primitives.button>

          <.agent_dialog
            :if={@detail}
            detail={@detail}
            same_person={same_person(@agents, @detail.agent)}
            notice={@notice}
            now={@now}
            lease={@lease}
            account={@account}
          />
        </:footer>
      </Regent.Account.agents>
    </div>
    """
  end

  # Each agent as the shared list shows it, newest first as the account reads them.
  defp rows(nil, _now), do: :loading
  defp rows(:unavailable, _now), do: :unavailable

  defp rows(agents, now) do
    Enum.map(agents, fn agent ->
      %{
        id: agent.id,
        name: agent.name,
        kind: to_string(agent.harness),
        harness: Harness.label(agent.harness),
        backed: HumanBacking.describe(agent).human_backed,
        last_contact_iso: DateTime.to_iso8601(agent.last_contact_at),
        last_contact: RegentFormat.relative_time(agent.last_contact_at, now)
      }
    end)
  end

  defp notice_text({_role, text}), do: text
  defp notice_text(nil), do: nil

  attr :id, :string, required: true
  attr :notice, :any, required: true

  defp agent_notice(%{notice: {role, text}} = assigns) do
    assigns = assign(assigns, role: role, text: text)

    ~H"""
    <p id={@id} class="account-agents__notice" role={to_string(@role)}>{@text}</p>
    """
  end

  defp agent_notice(assigns), do: ~H""

  # The person's other agents paired with this account, grouped by the World ID
  # person saved behind each.
  defp same_person(agents, %{id: id, human_id: human_id})
       when is_list(agents) and is_binary(human_id),
       do: Enum.filter(agents, &(&1.human_id == human_id and &1.id != id))

  defp same_person(_agents, _agent), do: []

  attr :detail, :map, required: true
  attr :same_person, :list, required: true
  attr :notice, :any, required: true
  attr :now, DateTime, required: true
  attr :lease, :any, required: true
  attr :account, :map, required: true

  defp agent_dialog(assigns) do
    ~H"""
    <dialog
      id="account-agent-dialog"
      class="account-agent-dialog"
      aria-labelledby="account-agent-dialog-title"
      phx-hook="InfoDialog"
      data-open
      data-close-event="close_agent"
    >
      <header class="account-agent-dialog__header">
        <Regent.Account.agent_mark kind={to_string(@detail.agent.harness)} />
        <div>
          <p class="account-kicker">{Harness.label(@detail.agent.harness)}</p>
          <h2 id="account-agent-dialog-title">{@detail.agent.name}</h2>
        </div>
      </header>

      <dl class="account-agent-dialog__facts">
        <div>
          <dt>First paired</dt>
          <dd>{moment(@detail.agent.paired_at)}</dd>
        </div>
        <div>
          <dt>Last contact</dt>
          <dd>
            {RegentFormat.relative_time(@detail.agent.last_contact_at, @now)}
            <span>{moment(@detail.agent.last_contact_at)}</span>
          </dd>
        </div>
        <div>
          <dt>Agent address</dt>
          <dd><code>{@detail.agent.wallet}</code></dd>
        </div>
        <div :if={@detail.listing}>
          <dt>Registry listing</dt>
          <dd>
            <a
              id="account-agent-registry-listing"
              href={@detail.listing.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              Agent #{@detail.listing.number}
            </a>
          </dd>
        </div>
        <div id="account-agent-human">
          <dt>Person</dt>
          <dd>
            <.human_backing
              backing={HumanBacking.describe(@detail.agent)}
              same_person={@same_person}
            />
          </dd>
        </div>
      </dl>

      <.live_component
        module={RegentsWeb.AgentPictureUpload}
        id="account-agent-picture"
        lease={@lease}
        account={@account}
        agent={@detail.agent}
      />

      <section class="account-agent-dialog__activity" aria-labelledby="account-agent-activity-title">
        <h3 id="account-agent-activity-title">Recent activity</h3>
        <p class="account-agent-dialog__note">
          The Regent sites this agent signed requests on since it paired, a line for each site and day, newest first. Kept for 30 days.
        </p>
        <.activity activity={@detail.activity} />
      </section>

      <.agent_notice id="account-agent-dialog-notice" notice={@notice} />

      <div class="account-agent-dialog__actions">
        <Regent.Primitives.button
          type="button"
          variant="secondary"
          phx-click="unpair_agent"
          phx-value-id={@detail.agent.id}
          data-confirm={"Unpair #{@detail.agent.name}? It will need a new code to pair again."}
        >
          Unpair
        </Regent.Primitives.button>
        <form method="dialog">
          <Regent.Primitives.button type="submit" value="close">Done</Regent.Primitives.button>
        </form>
      </div>
    </dialog>
    """
  end

  attr :backing, :map, required: true
  attr :same_person, :list, required: true

  # Two states only: a verified person stands behind the agent, or none does.
  # What each means waits in its tip; the person's World ID number is never shown.
  defp human_backing(%{backing: %{human_backed: true}} = assigns) do
    ~H"""
    <span class="account-agent-human account-agent-human--verified">
      <span class="account-agent-human__mark" aria-hidden="true">✓</span>
      Verified human
      <Regent.Primitives.tip id="account-agent-human-tip" label="About Verified human">
        A real person verified with World ID stands behind this agent. Who they are stays private.
      </Regent.Primitives.tip>
    </span>
    <span
      :if={@backing.same_person_agent_count >= 2}
      id="account-agent-same-person"
      class="account-agent-human__count"
    >
      1 of {@backing.same_person_agent_count} agents run by the same person
    </span>
    <span :if={@same_person != []} class="account-agent-human__others">
      <button
        :for={other <- @same_person}
        id={"account-agent-same-person-#{other.id}"}
        class="account-agent-human__other"
        type="button"
        phx-click="open_agent"
        phx-value-id={other.id}
      >
        {other.name}
      </button>
    </span>
    """
  end

  defp human_backing(assigns) do
    ~H"""
    <span class="account-agent-human">
      No verified human
      <Regent.Primitives.tip id="account-agent-human-tip" label="About No verified human">
        The agent's person can vouch for it with World ID.
        <a href="https://siwa.regents.sh/skill.md" target="_blank" rel="noopener noreferrer">
          Step 7
        </a>
      </Regent.Primitives.tip>
    </span>
    """
  end

  attr :activity, :any, required: true

  defp activity(%{activity: :loading} = assigns) do
    ~H"""
    <p role="status">Reading this agent’s activity…</p>
    """
  end

  defp activity(%{activity: :unavailable} = assigns) do
    ~H"""
    <p role="status">This agent’s activity couldn’t be read right now. Refresh to try again.</p>
    """
  end

  defp activity(%{activity: []} = assigns) do
    ~H"""
    <p role="status">No requests yet since it paired.</p>
    """
  end

  defp activity(assigns) do
    ~H"""
    <ol class="account-agent-dialog__log">
      <li :for={line <- @activity}>
        <span>{line.site}</span>
        <span>{hours(line.first_seen_at, line.last_seen_at)}</span>
        <time datetime={Date.to_iso8601(line.day)}>{Calendar.strftime(line.day, "%-d %B %Y")}</time>
      </li>
    </ol>
    """
  end

  # When the day's first and last request came, or the one time when they share
  # a minute.
  defp hours(first, last) do
    {from, to} = {Calendar.strftime(first, "%H:%M"), Calendar.strftime(last, "%H:%M")}
    if from == to, do: "#{to} UTC", else: "#{from} to #{to} UTC"
  end

  defp moment(datetime), do: Calendar.strftime(datetime, "%-d %B %Y, %H:%M UTC")
end
