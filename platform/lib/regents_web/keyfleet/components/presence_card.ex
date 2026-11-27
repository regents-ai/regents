defmodule RegentsWeb.Keyfleet.Components.PresenceCard do
  @moduledoc """
  Whether keys are present, and the button that marks them present: one key
  on its own page, or every key the signed-in wallet holds or holds a shard of
  on the fleet's proposals. A present key is counted when a proposal opens;
  an idle one can still vote, and joins the count when it does. The card shows
  the fleet's figures (`RegentsWeb.Keyfleet.Components.FleetFigures`).

  On the proposals the wallet's idle keys come first, above the button that
  marks them, and its present keys sit in a closed dropdown under it, so a long
  list of them never pushes the proposals down the page. A key's own page
  shows its one line as it is.
  """
  use RegentsWeb, :html

  alias Regents.Keyfleet.Fleets.Rules
  alias RegentsWeb.Keyfleet.Components.FleetFigures
  alias RegentsWeb.Keyfleet.WalletPanel
  alias RegentsWeb.Keyfleet.WalletWords

  attr :id, :string, required: true
  attr :fleet, :map, required: true, doc: "the fleet's `fleet_id` and `chain_id`"
  attr :actor, :any, required: true
  attr :lease, :map, required: true, doc: "the page's `session_lease`, or nil"
  attr :client_tag, :string, required: true, doc: "the page's `client_tag`"
  attr :token_id, :integer, default: nil, doc: "the one key, or nil for the wallet's own"
  attr :tool, :string, default: nil, doc: "the browser tool that presses Mark present, if any"
  attr :class, :any, default: nil

  attr :names_sender, :boolean,
    default: true,
    doc: "false where the page leaves out the line naming the sending wallet"

  attr :can_mark?, :boolean,
    default: true,
    doc: "false on a single-Key page when the viewer neither owns the Key nor holds a shard"

  def card(assigns) do
    ~H"""
    <section id={@id} class={@class} aria-labelledby={"#{@id}-title"}>
      <h2 id={"#{@id}-title"} class="presence-title">
        {if @token_id, do: "Quorum status", else: "Active quorum"}
      </h2>
      <.live_component
        module={WalletPanel}
        names_sender={@names_sender}
        id={"#{@id}-action"}
        flow={:present}
        fleet={@fleet}
        actor={@actor}
        lease={@lease}
        client_tag={@client_tag}
        token_id={@token_id}
        tool={@tool}
      >
        <:notes :let={panel}>
          <.key_lines :if={@token_id} id={"#{@id}-keys"} keys={keys(panel)} />
          <.key_lines :if={!@token_id} id={"#{@id}-idle"} keys={idle(panel)} />
        </:notes>
        <:buttons :let={panel}>
          <WalletPanel.step_button :if={@can_mark?} panel={panel} step="present" id={"#{@id}-mark"}>
            Mark present
          </WalletPanel.step_button>
        </:buttons>
        <:details :let={panel}>
          <Regent.Primitives.disclosure
            :if={!@token_id and present(panel) != []}
            id={"#{@id}-active"}
            summary={"Present Keys (#{length(present(panel))})"}
            class="presence-active"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <.key_lines id={"#{@id}-active-keys"} keys={present(panel)} />
          </Regent.Primitives.disclosure>
        </:details>
      </.live_component>
      <.live_component
        :if={is_nil(@token_id)}
        module={FleetFigures}
        id={"#{@id}-figures"}
        fleet_id={@fleet.fleet_id}
      />
      <Regent.Primitives.disclosure
        id={"#{@id}-rules"}
        summary="Quorum rules"
        class="presence-rules"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <p>
          A present Key counts toward quorum when a proposal opens. New Keys wait 2 days after sale,
          then count automatically until day 4. After that, marking present lasts 48 hours; voting or
          proposing renews presence too.
        </p>
      </Regent.Primitives.disclosure>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :keys, :list, required: true

  defp key_lines(assigns) do
    ~H"""
    <ul :if={@keys != []} id={@id} class="presence-keys">
      <li :for={key <- @keys} data-key={key.token_id}>
        <span>Key {Rules.grouped(key.token_id)}</span>
        <span :if={key.until} class="presence-on">
          Present until {WalletWords.at(key.until)}
        </span>
        <span :if={!key.until} class="presence-off">Not present</span>
      </li>
    </ul>
    """
  end

  defp keys(panel), do: panel |> WalletPanel.figures() |> Map.get(:keys, [])

  defp idle(panel), do: panel |> keys() |> Enum.filter(&is_nil(&1.until))

  defp present(panel), do: panel |> keys() |> Enum.reject(&is_nil(&1.until))
end
