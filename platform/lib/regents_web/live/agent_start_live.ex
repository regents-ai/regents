defmodule RegentsWeb.AgentStartLive do
  @moduledoc "The `/start` page: how a person connects their agent, one tab per agent."
  use RegentsWeb, :html

  alias RegentsWeb.AgentStart

  attr :agent, :string, default: nil, doc: "the chosen agent's id from `?agent=`"

  def page(assigns) do
    assigns = assign(assigns, agent: AgentStart.agent(assigns.agent), agents: AgentStart.agents())

    ~H"""
    <article id="agent-start-page" class="account-page agent-start">
      <header class="account-heading">
        <p class="account-kicker">Agents</p>
        <h1 tabindex="-1">Connect your agent</h1>
        <p class="account-lede">
          It reads your account for you. It can never use your wallet, change your account or pair other agents.
        </p>
      </header>

      <section class="account-panel agent-start__handoff" aria-labelledby="agent-start-give">
        <nav class="agent-start__tabs" aria-label="Which agent?">
          <.link
            :for={agent <- @agents}
            patch={~p"/start?#{[agent: agent.id]}"}
            aria-current={if agent.id == @agent.id, do: "page"}
          >{agent.label}</.link>
        </nav>
        <div class="agent-start__head">
          <label id="agent-start-give" for="agent-start-text">Give this to your agent</label>
          <Regent.Primitives.copy_button
            id="agent-start-copy"
            target="agent-start-text"
            aria-label={"Copy the steps for #{@agent.label}"}
          >Copy</Regent.Primitives.copy_button>
        </div>
        <textarea id="agent-start-text" readonly rows="16">{AgentStart.instruction(@agent)}</textarea>
      </section>

      <section class="account-panel" aria-labelledby="agent-start-steps-title">
        <h2 id="agent-start-steps-title">What happens</h2>
        <ol class="agent-start__steps">
          <li>
            <h3>Make a code</h3>
            <p>
              Sign in, then open Pair New Agent on your Account page and choose your agent. The code works once, for ten minutes.
            </p>
            <.link navigate={~p"/account#account-pairing"}>Pair New Agent</.link>
          </li>
          <li>
            <h3>Your agent pairs</h3>
            <p>It shows in your account menu under its name.</p>
          </li>
          <li>
            <h3>It reads for you</h3>
            <p>Your balance, Credits, names, Points and staking.</p>
          </li>
          <li>
            <h3>Spending</h3>
            <p>Agent spending opens soon.</p>
          </li>
        </ol>
      </section>
    </article>
    """
  end
end
