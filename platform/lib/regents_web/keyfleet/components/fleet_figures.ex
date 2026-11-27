defmodule RegentsWeb.Keyfleet.Components.FleetFigures do
  @moduledoc """
  A fleet's three figures, read when the page loads: the Keys a proposal opening
  now would count, those with a day or less left, and the Keys counted on the
  soonest open proposal that haven't voted. A figure that can't be read shows a
  dash.
  """
  use RegentsWeb, :live_component

  alias Regents.Keyfleet.Keys
  alias RegentsWeb.Keyfleet.FleetProposals

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(changed?(socket, :fleet_id), do: read(socket), else: socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <dl id={@id} class="fleet-figures">
      <div>
        <dt>
          <Regent.Primitives.tip id={"#{@id}-present-tip"}>
            <:figure>Present</:figure>
            Active seats counted when a new proposal opens. Stay present by voting, proposing, or checking in every 48 hours.
          </Regent.Primitives.tip>
        </dt>
        <dd id={"#{@id}-present"}>{figure(@present)}</dd>
      </div>
      <div>
        <dt>
          <Regent.Primitives.tip id={"#{@id}-expiring-tip"}>
            <:figure>Expiring</:figure>
            Present seats dropping out within 24 hours unless they check in, vote, or propose.
          </Regent.Primitives.tip>
        </dt>
        <dd id={"#{@id}-expiring"}>{figure(@expiring)}</dd>
      </div>
      <div>
        <dt>
          <Regent.Primitives.tip id={"#{@id}-undecided-tip"}>
            <:figure>Undecided</:figure>
            Counted seats that have not voted on the soonest open proposal. Non-votes count against passing.
          </Regent.Primitives.tip>
        </dt>
        <dd id={"#{@id}-undecided"}>{figure(@undecided)}</dd>
      </div>
    </dl>
    """
  end

  defp read(%{assigns: %{fleet_id: fleet_id}} = socket) do
    counts =
      case Keys.presence_counts(fleet_id) do
        {:ok, counts} -> counts
        {:error, _failure} -> %{present: nil, expiring: nil}
      end

    socket |> assign(counts) |> assign(undecided: undecided(FleetProposals.open(fleet_id)))
  end

  defp undecided(proposals) do
    case Enum.find(proposals, &(&1.status == :open)) do
      nil -> nil
      %{counted: counted, yes: yes, no: no, abstain: abstain} -> counted - yes - no - abstain
    end
  end

  defp figure(nil), do: "—"
  defp figure(count), do: count
end
