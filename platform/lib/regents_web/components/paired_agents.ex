defmodule RegentsWeb.Components.PairedAgents do
  @moduledoc """
  The agents a person has paired with their account: a card for each, a way to
  pair another, and a larger view of one agent with what it has been doing
  across the Regents sites.
  """

  use RegentsWeb, :html

  alias RegentAgents.{Harness, HumanBacking, PairingCode}

  # Stands in for a code before one is made, so the message keeps its size.
  @no_code String.duplicate("X", 24)

  @logos %{
    hermes: "/images/agents/hermes.png",
    grok_bot: "/images/agents/grok-bot.png",
    muse: "/images/agents/muse.png",
    openclaw: "/images/agents/openclaw.png",
    nemoclaw: "/images/agents/nemoclaw.png",
    ironclaw: "/images/agents/ironclaw.png",
    pi: "/images/agents/pi.svg",
    claude_code: "/images/agents/claude-code.png",
    codex: "/images/agents/codex.png",
    cursor: "/images/agents/cursor.png",
    gemini_cli: "/images/agents/gemini-cli.png",
    dots: "/images/agents/dots.png",
    other: "/images/agents/other.svg"
  }

  attr :agents, :any, required: true
  attr :pairing, :map, default: nil, doc: "`%{harness, code}` once an agent is chosen"
  attr :detail, :map, default: nil
  attr :notice, :any, default: nil, doc: "`{:status | :alert, text}` for the last agent edit"
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

      <.agent_notice :if={is_nil(@detail)} id="account-agents-notice" notice={@notice} />
      <.agent_list agents={@agents} now={@now} />

      <div class="account-agents__pair">
        <h3 id="account-agents-pair-title">
          Select your personal agent you will pair to your Regents Account
        </h3>
        <form id="account-agents-choose" phx-change="issue_pairing_code">
          <fieldset class="account-agents__choices" aria-labelledby="account-agents-pair-title">
            <label :for={harness <- Harness.values()} class="account-agents__choice">
              <input
                type="radio"
                name="harness"
                value={harness}
                checked={match?(%{harness: ^harness}, @pairing)}
                class="visually-hidden"
              />
              <.harness_mark harness={harness} />{Harness.label(harness)}
            </label>
          </fieldset>
        </form>
        <.pairing pairing={@pairing} />
      </div>

      <.agent_dialog
        :if={@detail}
        detail={@detail}
        same_person={same_person(@agents, @detail.agent)}
        notice={@notice}
        now={@now}
      />
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
    ~H"""
    <p class="account-agents__empty">
      No agents are paired yet. Choose yours below and give it the message.
    </p>
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
              {RegentFormat.relative_time(agent.last_contact_at, @now)}
            </time>
          </span>
          <span class="account-agent__more" aria-hidden="true">See what it has done →</span>
        </button>
      </li>
    </ul>
    """
  end

  attr :pairing, :map, default: nil

  # One layout for every state, so choosing an agent never changes the panel's
  # height: each agent's message sits in the same place, and what a state lacks
  # keeps its space, unseen.
  defp pairing(assigns) do
    {harness, code} =
      case assigns.pairing do
        %{harness: harness, code: code} -> {harness, code}
        nil -> {nil, nil}
      end

    issued = match?(%PairingCode.Issued{}, code)
    shown_code = if issued, do: code.code, else: @no_code

    assigns =
      assign(assigns,
        harness: harness,
        code: code,
        issued: issued,
        message: if(issued, do: agent_message(shown_code, harness)),
        messages: Harness.values() |> Enum.map(&agent_message(shown_code, &1)) |> Enum.uniq(),
        expires_at: if(issued, do: code.expires_at)
      )

    ~H"""
    <div id="account-agents-pairing" class="account-agents__code">
      <ol class="account-agents__steps">
        <li>Copy this message.</li>
        <li>Paste it to your agent wherever you chat with it.</li>
        <li>Your agent appears here once it pairs. This page updates on its own.</li>
      </ol>
      <div class="account-agents__message" role="status">
        <pre :for={message <- @messages} data-unused={message != @message}><code>{message}</code></pre>
        <.pairing_words code={@code} />
      </div>
      <div class="account-agents__actions">
        <Regent.Primitives.copy_button
          id="account-agents-copy"
          text={@message || ""}
          variant="primary"
          data-unused={!@issued}
        >
          Copy message
        </Regent.Primitives.copy_button>
        <Regent.Primitives.button
          id="account-agents-pair"
          type="button"
          variant="secondary"
          phx-click="issue_pairing_code"
          phx-value-harness={@harness}
          phx-disable-with="Making a code…"
          data-unused={is_nil(@harness)}
        >
          Make a new code
        </Regent.Primitives.button>
      </div>
      <p class="account-agents__expiry" data-unused={!@issued}>
        The code works once, until <.expiry expires_at={@expires_at} />.
      </p>
    </div>
    """
  end

  attr :code, :any, required: true

  defp pairing_words(%{code: nil} = assigns) do
    ~H"""
    <p class="account-agents__words">Choose your agent to get its message.</p>
    """
  end

  defp pairing_words(%{code: {:paired, agent}} = assigns) do
    assigns = assign(assigns, :agent, agent)

    ~H"""
    <p class="account-agents__words account-agents__paired">
      {@agent.name} paired with your account. Its card is above; open it to see what it does.
    </p>
    """
  end

  defp pairing_words(%{code: :unavailable} = assigns) do
    ~H"""
    <p class="account-agents__words">
      A pairing code couldn’t be made right now. Try again in a moment.
    </p>
    """
  end

  defp pairing_words(assigns), do: ~H""

  attr :expires_at, :any, required: true, doc: "a `DateTime`, or nil before a code is made"

  defp expiry(%{expires_at: nil} = assigns), do: ~H"<time>00:00 UTC</time>"

  defp expiry(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@expires_at)}>{Calendar.strftime(@expires_at, "%H:%M UTC")}</time>
    """
  end

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
        <.more_activity :if={is_list(@detail.activity) and is_binary(@detail.next)} detail={@detail} />
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

  attr :detail, :map, required: true

  defp more_activity(assigns) do
    ~H"""
    <div class="account-agent-dialog__more">
      <Regent.Primitives.button
        id="account-agent-load-more"
        type="button"
        variant="secondary"
        phx-click="load_more_activity"
        phx-value-id={@detail.agent.id}
        disabled={@detail.more == :loading}
      >
        {if @detail.more == :loading, do: "Loading…", else: "Load more"}
      </Regent.Primitives.button>
      <p :if={@detail.more == :unavailable} id="account-agent-load-more-notice" role="status">
        Older activity couldn’t be read right now. Try again.
      </p>
    </div>
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

  # What the person pastes to their agent. Muse runs where siwa.regents.sh may
  # not answer, so its message names the SIWA service's other address.
  defp agent_message(code, :muse) do
    agent_message(code, nil) <>
      "\nIf siwa.regents.sh doesn't answer from your host, set " <>
      "SIWA_BROKER=https://siwa-server.fly.dev and try again."
  end

  defp agent_message(code, _harness) do
    """
    Pair with my Regents account.
    Pairing code: #{code}
    Follow the "Pair with a person's account" steps at https://regents.sh/llms.txt\
    """
  end

  defp moment(datetime), do: Calendar.strftime(datetime, "%-d %B %Y, %H:%M UTC")
end
