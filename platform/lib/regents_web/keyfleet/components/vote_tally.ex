defmodule RegentsWeb.Keyfleet.Components.VoteTally do
  @moduledoc """
  How a proposal's vote stands at a glance: one bar split by Keys, and the
  counts beside it, so six against forty-nine reads as that at once.
  """

  use Phoenix.Component

  alias Regents.Keyfleet.Fleets.Rules

  attr :yes, :integer, required: true
  attr :no, :integer, required: true
  attr :abstain, :integer, default: 0

  def vote_tally(assigns) do
    assigns =
      assign(assigns,
        sides:
          for(
            {side, count} <- [yes: assigns.yes, no: assigns.no, abstain: assigns.abstain],
            count > 0,
            do: {side, count}
          )
      )

    ~H"""
    <span class="vote-tally">
      <span class="vote-tally__bar" aria-hidden="true">
        <span :for={{side, count} <- @sides} data-side={side} style={"flex-grow: #{count}"}></span>
      </span>
      <span class="vote-tally__counts">
        <span data-side="yes">{Rules.grouped(@yes)} yes</span>
        <span data-side="no">{Rules.grouped(@no)} no</span>
        <span :if={@abstain > 0} data-side="abstain">{Rules.grouped(@abstain)} abstain</span>
      </span>
    </span>
    """
  end
end
