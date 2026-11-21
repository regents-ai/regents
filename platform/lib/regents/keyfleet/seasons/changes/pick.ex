defmodule Regents.Keyfleet.Seasons.Changes.Pick do
  @moduledoc """
  Places a Key's pick in the season the caller names, while that season still
  takes picks: not yet started, and not yet locked by its turn.

  The season is read under a shared lock, so a turn locking it at that moment
  either takes this pick or turns it away, never both. The product must be
  open to picks by the list read last (`Regents.Keyfleet.Seasons.CoinList`).
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Regents.Keyfleet.Polls
  alias Regents.Keyfleet.Rooms.Errors.NoKeyToWriteAsError
  alias Regents.Keyfleet.Seasons
  alias Regents.Keyfleet.Seasons.CoinList
  alias Regents.Keyfleet.Seasons.Errors.PicksClosedError
  alias Regents.Keyfleet.Seasons.Errors.ProductIneligibleError
  alias Regents.Keyfleet.Seasons.Errors.ProductsUnreadError
  alias Regents.Keyfleet.Seasons.Errors.SeasonUnknownError
  alias Regents.Keyfleet.Seasons.Season

  @impl true
  def change(changeset, _opts, %{actor: actor}),
    do: Ash.Changeset.before_action(changeset, &place(&1, actor))

  defp place(changeset, actor) do
    fleet_id = Ash.Changeset.get_argument(changeset, :fleet_id)
    number = Ash.Changeset.get_argument(changeset, :number)

    with {:ok, season} <- season(fleet_id, number),
         :ok <- taking_picks(season),
         {:ok, %{key: key, wallet: wallet}} <- picker(actor, fleet_id),
         :ok <- eligible(Ash.Changeset.get_attribute(changeset, :product)) do
      Ash.Changeset.force_change_attributes(changeset, %{
        season_id: season.id,
        token_id: key,
        wallet: wallet
      })
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # The pick itself was authorized, by the actor's standing in the fleet.
  defp season(fleet_id, number) do
    Season
    |> Ash.Query.filter(fleet_id == ^fleet_id and number == ^number)
    |> Ash.Query.lock("FOR SHARE")
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> {:error, SeasonUnknownError.exception(number: number)}
      season -> {:ok, season}
    end
  end

  defp taking_picks(season) do
    if Seasons.taking_picks?(season),
      do: :ok,
      else: {:error, PicksClosedError.exception(number: season.number)}
  end

  defp picker(actor, fleet_id) do
    case Polls.voter(actor, fleet_id) do
      nil -> {:error, NoKeyToWriteAsError.exception(fleet_id: fleet_id)}
      picker -> {:ok, picker}
    end
  end

  defp eligible(product) do
    case CoinList.check(product) do
      :ok -> :ok
      {:error, :ineligible} -> {:error, ProductIneligibleError.exception(product: product)}
      {:error, :unavailable} -> {:error, ProductsUnreadError.exception([])}
    end
  end
end
