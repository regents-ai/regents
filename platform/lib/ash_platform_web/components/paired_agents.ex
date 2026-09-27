defmodule AshPlatformWeb.Components.PairedAgents do
  @moduledoc """
  The agents a person has paired with their account: a card for each, a way to
  pair another, and a larger view of one agent with what it has been doing
  across the Regents sites.
  """

  use AshPlatformWeb, :html

  alias AshPlatform.Agents.{Harness, PairingCode}

  @logos %{
    hermes: "/images/agents/hermes.png",
    grok_bot: "/images/agents/grok-bot.png",
    muse: "/images/agents/muse.png",
    openclaw: "/images/agents/openclaw.png",
    nemoclaw: "/images/agents/nemoclaw.png",
    ironclaw: "/images/agents/ironclaw.png",
    pi: "/images/agents/pi.svg"
  }

  attr :agents, :any, required: true
  attr :pairing, :any, default: nil
  attr :detail, :map, default: nil
  attr :now, DateTime, required: true

  def paired_agents(assigns) do
    ~H"""
    <section
      id="account-agents"
      class="account-panel account-agents"
      aria-labelledby="account-agents-title"
    >
      <div class="account-names__heading">
        <h2 id="account-agents-title">Your agents</h2>
        <p>Agents you have paired with this account, most recent first.</p>
      </div>

      <.agent_list agents={@agents} now={@now} />

      <div class="account-agents__pair">
        <Regent.Primitives.button
          id="account-agents-pair"
          type="button"
          variant="secondary"
          phx-click="issue_pairing_code"
          phx-disable-with="Making a code…"
        >
          {if match?(%PairingCode.Issued{}, @pairing), do: "Make a new code", else: "Pair an agent"}
        </Regent.Primitives.button>
        <.pairing pairing={@pairing} />
      </div>

      <.agent_dialog :if={@detail} detail={@detail} now={@now} />
    </section>
    """
  end

  attr :agents, :any, required: true
  attr :now, DateTime, required: true

  defp agent_list(%{agents: :unavailable} = assigns) do
    ~H"""
    <p role="status">Your agents couldn’t be read right now. Refresh to try again.</p>
    """
  end

  defp agent_list(%{agents: []} = assigns) do
    assigns = assign(assigns, :runtimes, Harness.values())

    ~H"""
    <div class="account-agents__empty">
      <p>No agents are paired yet. Make a pairing code and give it to your agent.</p>
      <p class="account-agents__runtimes">
        Works with agents on
        <span :for={harness <- @runtimes} class="account-agents__runtime">
          <.harness_mark harness={harness} />{Harness.label(harness)}
        </span>
      </p>
    </div>
    """
  end

  defp agent_list(assigns) do
    ~H"""
    <ul id="account-agent-cards" class="account-agents__cards">
      <li :for={agent <- @agents} id={"agent-#{agent.id}"} class="account-agent">
        <button
          type="button"
          class="account-agent__open"
          phx-click="open_agent"
          phx-value-id={agent.id}
          aria-label={"#{agent.name}, #{Harness.label(agent.harness)}. See what it has done"}
        >
          <.harness_mark harness={agent.harness} />
          <span class="account-agent__who">
            <strong>{agent.name}</strong>
            <span>{Harness.label(agent.harness)}</span>
          </span>
          <span class="account-agent__contact">
            Last contact
            <time datetime={DateTime.to_iso8601(agent.last_contact_at)}>
              {ago(agent.last_contact_at, @now)}
            </time>
          </span>
          <span class="account-agent__more" aria-hidden="true">See what it has done →</span>
        </button>
      </li>
    </ul>
    """
  end

  attr :pairing, :any, default: nil

  defp pairing(%{pairing: nil} = assigns), do: ~H""

  defp pairing(%{pairing: :wait} = assigns) do
    ~H"""
    <p id="account-agents-pairing" role="status">
      A new code can be made once a minute. Try again shortly.
    </p>
    """
  end

  defp pairing(%{pairing: {:paired, agent}} = assigns) do
    assigns = assign(assigns, :agent, agent)

    ~H"""
    <p id="account-agents-pairing" class="account-agents__paired" role="status">
      {@agent.name} paired with your account. Its card is above; open it to see what it does.
    </p>
    """
  end

  defp pairing(%{pairing: :unavailable} = assigns) do
    ~H"""
    <p id="account-agents-pairing" role="status">
      A pairing code couldn’t be made right now. Try again in a moment.
    </p>
    """
  end

  defp pairing(assigns) do
    assigns =
      assign(assigns,
        message: agent_message(assigns.pairing.code),
        expires: Calendar.strftime(assigns.pairing.expires_at, "%H:%M UTC"),
        expires_iso: DateTime.to_iso8601(assigns.pairing.expires_at)
      )

    ~H"""
    <div id="account-agents-pairing" class="account-agents__code" role="status">
      <ol class="account-agents__steps">
        <li>Copy this message.</li>
        <li>Paste it to your agent wherever you chat with it.</li>
        <li>Your agent appears here once it pairs. This page updates on its own.</li>
      </ol>
      <pre><code>{@message}</code></pre>
      <Regent.Primitives.copy_button id="account-agents-copy" text={@message} variant="primary">
        Copy message
      </Regent.Primitives.copy_button>
      <p class="account-agents__expiry">
        The code works once, until <time datetime={@expires_iso}>{@expires}</time>.
      </p>
    </div>
    """
  end

  attr :detail, :map, required: true
  attr :now, DateTime, required: true

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
        <.harness_mark harness={@detail.agent.harness} />
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
            {ago(@detail.agent.last_contact_at, @now)}
            <span>{moment(@detail.agent.last_contact_at)}</span>
          </dd>
        </div>
        <div>
          <dt>Agent address</dt>
          <dd><code>{@detail.agent.wallet}</code></dd>
        </div>
        <div>
          <dt><label for="account-agent-harness">Runs on</label></dt>
          <dd>
            <form id="account-agent-harness-form" phx-change="change_agent_harness">
              <input type="hidden" name="agent" value={@detail.agent.id} />
              <select id="account-agent-harness" name="harness">
                <option
                  :for={harness <- Harness.values()}
                  value={harness}
                  selected={harness == @detail.agent.harness}
                >
                  {Harness.label(harness)}
                </option>
              </select>
            </form>
          </dd>
        </div>
      </dl>

      <section class="account-agent-dialog__activity" aria-labelledby="account-agent-activity-title">
        <h3 id="account-agent-activity-title">Recent activity</h3>
        <p class="account-agent-dialog__note">
          Every request this agent signed on a Regents site since it paired, newest first. Kept for 30 days.
        </p>
        <.activity activity={@detail.activity} />
      </section>

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

  defp activity(assigns) do
    ~H"""
    <ol class="account-agent-dialog__log">
      <li :for={entry <- @activity}>
        <span>{entry.action}</span>
        <span>{entry.site}</span>
        <time datetime={DateTime.to_iso8601(entry.occurred_at)}>{moment(entry.occurred_at)}</time>
      </li>
    </ol>
    """
  end

  attr :harness, :atom, required: true

  defp harness_mark(assigns) do
    assigns = assign(assigns, :logo, Map.fetch!(@logos, assigns.harness))

    ~H"""
    <span class="account-agent__mark" aria-hidden="true">
      <img src={@logo} alt="" width="48" height="48" />
    </span>
    """
  end

  defp agent_message(code) do
    """
    Pair with my Regents account.
    Pairing code: #{code}
    Follow the "Pair with a person's account" steps at https://regents.sh/llms.txt\
    """
  end

  defp moment(datetime), do: Calendar.strftime(datetime, "%-d %B %Y, %H:%M UTC")

  defp ago(datetime, now) do
    case DateTime.diff(now, datetime, :second) do
      seconds when seconds < 60 -> "just now"
      seconds when seconds < 120 -> "a minute ago"
      seconds when seconds < 3_600 -> "#{div(seconds, 60)} minutes ago"
      seconds when seconds < 7_200 -> "an hour ago"
      seconds when seconds < 86_400 -> "#{div(seconds, 3_600)} hours ago"
      seconds when seconds < 172_800 -> "yesterday"
      seconds -> "#{div(seconds, 86_400)} days ago"
    end
  end
end
