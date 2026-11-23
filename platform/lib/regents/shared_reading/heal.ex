defmodule Regents.SharedReading.Heal do
  @moduledoc """
  Asks the producer of one kind of shared reading to read all its keys again
  (`Regents.SharedReading.heal/1`) when at least one product owning that reading
  has active route traffic (`Regents.ProductActivity`). One attempt: the next
  run replaces a failed one.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Regents.ProductActivity

  @products %{
    points_board: [:points],
    keyfleet_season_coins: [:keyfleet],
    keyfleet_fleet_agents: [:keyfleet],
    keyfleet_key_agents: [:keyfleet],
    keyfleet_fleet_now: [:keyfleet],
    keyfleet_fleet_proposals: [:keyfleet],
    keyfleet_fleet_treasury: [:keyfleet],
    keyfleet_share_card: [:keyfleet],
    keyfleet_project_cards: [:keyfleet],
    keyfleet_proposal: [:keyfleet],
    wallet_bench: [:patchbay, :techtree],
    hidden_sites: [:patchbay]
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"kind" => kind}}) do
    kind = String.to_existing_atom(kind)
    products = Map.get(@products, kind, [])

    if products == [] or Enum.any?(products, &ProductActivity.active?/1) do
      Regents.SharedReading.heal(kind)
    else
      :ok
    end
  end
end
