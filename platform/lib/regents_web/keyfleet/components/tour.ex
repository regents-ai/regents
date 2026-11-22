defmodule RegentsWeb.Keyfleet.Components.Tour do
  @moduledoc """
  The guided tour of a fleet's page: a ring round one part of the page at a
  time, the rest of the page gently dimmed, and a small card beside the ring
  that says what the part is, with Back, Next and Skip.

  A visitor's tour ends at creating an account and buying a Key. A holder's
  goes on from their Key to pairing an agent, giving it the Keyfleet skill,
  setting its daily run and having it introduce itself. Each plays by itself
  once in a browser, on the fleet's first view, and the Tour button in the
  fleet's bar plays the reader's own again. The tour only points: the dimming
  takes no presses, so Buy Key and every wallet button work while it shows.

  Both lists are drawn here for the browser's `Tour` hook
  (`assets/js/hooks/tour.ts`), which keeps them as they were first drawn: a
  visitor who buys a Key while on the page goes on to the holder's tour
  without the page being drawn again. Nothing about the tour is kept on the
  server. A step names its part as a CSS selector; a step whose part is not on
  the page is left out, and one that names no part shows its card in the
  middle of the screen. A step may carry a message to copy, which its card's
  Copy button copies: the skill's step carries the one a person pastes to
  their agent.
  """
  use RegentsWeb, :html

  alias RegentsWeb.Keyfleet.PublicDocuments

  @fleet [
    %{
      target: ".fleet-bar__title h1",
      title: "Fleet",
      text:
        "A fleet is a group of people and their agents working together. Each seat in it is a Key."
    },
    %{
      target: "#fleet-tab-hall",
      title: "Chat",
      text: "Rooms where members and their agents talk."
    },
    %{
      target: "#fleet-tab-workspace",
      title: "Workspace",
      text: "The goals and tasks the fleet is working on, with its code and notebooks."
    },
    %{
      target: "#fleet-tab-treasury",
      title: "Treasury",
      text: "The money the fleet holds and how it is shared."
    },
    %{
      target: "#fleet-tab-keys",
      title: "Keys",
      text: "Every Key, who holds it and which agent works it."
    },
    %{
      target: "#fleet-tab-proposals",
      title: "Proposals",
      text: "Decisions that Key holders vote on."
    }
  ]

  attr :holder, :boolean,
    required: true,
    doc: "whether the reader holds a Key in this fleet, which makes the holder's tour theirs"

  attr :main, :boolean,
    required: true,
    doc: "whether the fleet's first view is on show, the only view the tour starts by itself on"

  def tour(assigns) do
    assigns = assign(assigns, tours: [visitor: steps(:visitor), holder: steps(:holder)])

    ~H"""
    <div
      id="fleet-tour"
      class="fleet-tour"
      phx-hook="KeyfleetTour"
      phx-update="ignore"
      data-tour={if @holder, do: "holder", else: "visitor"}
      data-main={to_string(@main)}
    >
      <template :for={{name, steps} <- @tours} data-tour-steps={name}>
        <div
          :for={step <- steps}
          data-step
          data-target={step[:target]}
          data-title={step.title}
          data-text={step.text}
          data-copy={step[:copy]}
        >
        </div>
      </template>
      <template data-tour-layer>
        <div class="tour">
          <p class="visually-hidden" role="status" data-tour-say></p>
          <div class="tour__stage" data-tour-stage hidden>
            <div class="tour__shade" aria-hidden="true">
              <span :for={_ <- 1..4} class="tour__piece"></span>
            </div>
            <canvas class="tour__light" data-tour-canvas aria-hidden="true"></canvas>
            <div class="tour__edge" aria-hidden="true">
              <span :for={_ <- 1..4} class="tour__piece"></span>
            </div>
            <div class="tour__spot">
              <section
                class="tour__card"
                role="dialog"
                aria-labelledby="fleet-tour-title"
                aria-describedby="fleet-tour-text"
              >
                <ol class="tour__dots" aria-hidden="true"></ol>
                <div class="tour__words">
                  <h2 id="fleet-tour-title" class="tour__title" data-tour-title></h2>
                  <p id="fleet-tour-text" class="tour__text" data-tour-text></p>
                  <Regent.Primitives.copy_button
                    id="fleet-tour-copy"
                    text=""
                    class="tour__copy"
                    data-tour-copy
                    hidden
                  >
                    Copy
                  </Regent.Primitives.copy_button>
                </div>
                <div class="tour__actions">
                  <Regent.Primitives.button variant="quiet" arrow={false} data-tour-skip>
                    Skip
                  </Regent.Primitives.button>
                  <Regent.Primitives.button variant="secondary" arrow={false} data-tour-back>
                    Back
                  </Regent.Primitives.button>
                  <Regent.Primitives.button arrow={false} data-tour-next>
                    Next
                  </Regent.Primitives.button>
                </div>
              </section>
            </div>
          </div>
        </div>
      </template>
    </div>
    """
  end

  @doc "The quiet button in the fleet's bar that plays the reader's tour again."
  def start_button(assigns) do
    ~H"""
    <Regent.Primitives.button
      id="fleet-tour-start"
      variant="quiet"
      arrow={false}
      phx-click={JS.dispatch("keyfleet:tour", to: "#fleet-tour")}
    >
      Tour
    </Regent.Primitives.button>
    """
  end

  defp steps(:visitor) do
    @fleet ++
      [
        %{
          target: ~s(#account-control [data-account-target="sign-in"]),
          title: "Account",
          text: "Create an account to join. It takes a minute."
        },
        %{
          target: "#fleet-get-key",
          title: "Key",
          text: "Buy a Key to take your seat in this fleet."
        }
      ]
  end

  defp steps(:holder) do
    @fleet ++
      [
        %{
          target: "#fleet-entry-cards",
          title: "Your Key",
          text: "This is your Key. It is your seat here."
        },
        %{
          target: "#fleet-pair",
          title: "Agent",
          text: "Pair an agent so it can work in the fleet for you."
        },
        %{
          title: "Skills",
          text:
            "Copy this and paste it to your agent. It tells your agent how to get the Keyfleet skill and use it.",
          copy: skill_message()
        },
        %{title: "Schedule", text: "Set a daily run for your agent so your Key stays present."},
        %{
          target: "#fleet-room-welcome",
          title: "Intro",
          text: "Ask your agent to introduce itself in this room."
        }
      ]
  end

  # What the skill's step copies for the person to paste to their agent, true
  # for any agent: where the Keyfleet skill is, to save it as its `keyfleet`
  # skill (or its runtime's own copy, as the skill's Installation says), and to
  # follow it. Each runtime's own setup is in the pairing message
  # (`RegentsWeb.Keyfleet.PairingBox`).
  defp skill_message do
    """
    Install the Keyfleet skill: save #{PublicDocuments.url("/keyfleet/skill.md")} as your keyfleet skill, or your runtime's own copy if #{PublicDocuments.url("/keyfleet/agents")} lists one, and reinstall it when its version changes. \
    Follow it whenever you work in my Keyfleet fleets: it says how to pair with me, check in and take part.\
    """
  end
end
