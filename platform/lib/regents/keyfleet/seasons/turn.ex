defmodule Regents.Keyfleet.Seasons.Turn do
  @moduledoc """
  A fleet's turn at a boundary, queued by `Regents.Keyfleet.Seasons.Turns` a minute
  after it and every ten minutes until the next. It brings the fleet's seasons up to that boundary, one boundary at
  a time and in order, so a fleet left behind by downtime catches up from
  Coinbase's candle history.

  At each boundary, in one transaction: the season that ended there is
  settled (each pick's close price and result, and the holding's own), the
  crown is decided (`Regents.Keyfleet.Seasons.Rules.crown/2`), the season starting
  there is locked (each pick checked as open to picks again and given its open
  price, or made void, and the new holding's open price), and the season after
  it is opened for picks. A fleet with no seasons yet opens its first, to start
  at the next boundary.

  Everything Coinbase is asked comes first, outside the transaction. If any of
  it can't be read, nothing is written and the job fails, for Oban to try
  again. The starting season is then locked for update: a turn that finds it
  already locked has nothing to do, so a job run twice, or late, changes
  nothing more. A pick that came in before the lock with a product not asked
  about fails the turn the same way, to be read again.

  It has its own queue, one job at a time: each turn waits on Coinbase for up
  to a minute or so, and in `default` it would hold back the site's quick
  jobs, while behind the other outside services' queues it would wait on
  them.
  """
  use Oban.Worker,
    queue: :keyfleet_seasons,
    max_attempts: 10,
    unique: [keys: [:fleet_id, :boundary], period: :infinity, states: :incomplete]

  require Ash.Query

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Seasons
  alias Regents.Keyfleet.Seasons.Coinbase
  alias Regents.Keyfleet.Seasons.Rules
  alias Regents.Keyfleet.Seasons.Season
  alias Regents.Keyfleet.Seasons.SeasonPick

  @usdc "USDC"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fleet_id" => fleet_id, "boundary" => boundary}}) do
    {:ok, boundary, 0} = DateTime.from_iso8601(boundary)
    turn(fleet_id, boundary)
  end

  defp turn(fleet_id, boundary) do
    case latest(fleet_id) do
      nil -> open(fleet_id, 1, Seasons.ends_at(boundary))
      %Season{locked_at: nil} = starting -> catch_up(starting, boundary)
    end
  end

  # The season taking picks starts after the boundary once the fleet is up to it.
  defp catch_up(%Season{starts_at: starts_at} = starting, boundary) do
    if DateTime.after?(starts_at, boundary) do
      :ok
    else
      with :ok <- step(starting), do: turn(starting.fleet_id, boundary)
    end
  end

  defp step(%Season{} = starting) do
    ended = ended(starting)
    scored = if ended, do: locked_picks(ended), else: []
    asked = starting |> picks() |> Enum.map(& &1.product) |> Enum.uniq()

    with {:ok, eligible} <- Coinbase.eligible_among(asked),
         {:ok, prices} <- prices(priced(ended, scored, eligible), starting.starts_at),
         read = %{asked: asked, eligible: eligible, prices: prices},
         {:ok, :ok} <-
           Ash.transact([Season, SeasonPick], fn -> turn_over(starting, ended, scored, read) end),
         do: :ok
  end

  defp turn_over(starting, ended, scored, read) do
    with %Season{locked_at: nil} = starting <- for_update(starting),
         {:ok, picks} <- asked_about(picks(starting), read.asked) do
      crown = settle(ended, scored, read.prices)
      lock(starting, picks, crown, read)
      open(starting.fleet_id, starting.number + 1, starting.ends_at)
    else
      %Season{} -> :ok
      {:error, _changed} = error -> error
    end
  end

  defp settle(nil, [], _prices), do: Rules.crown(nil, [])

  defp settle(%Season{} = ended, picks, prices) do
    closed =
      Enum.map(picks, &update!(&1, :close, Rules.closing(&1, prices)))

    close = Map.fetch!(prices, ended.holding)

    ended
    |> update!(:settle, %{
      holding_close_price: close,
      holding_result: Rules.result(ended.holding_open_price, close)
    })
    |> Rules.crown(closed)
  end

  defp lock(starting, picks, {holding, captain}, %{eligible: eligible, prices: prices}) do
    Enum.each(picks, &update!(&1, :open, Rules.opening(&1, eligible, prices)))

    update!(starting, :lock, %{
      holding: holding,
      captain_key: captain,
      holding_open_price: Map.fetch!(prices, holding)
    })
  end

  defp open(fleet_id, number, starts_at) do
    Season
    |> Ash.Changeset.for_create(
      :open,
      %{fleet_id: fleet_id, number: number, starts_at: starts_at},
      actor: %System{}
    )
    |> Ash.create!()

    :ok
  end

  defp update!(record, action, attributes),
    do: record |> Ash.Changeset.for_update(action, attributes, actor: %System{}) |> Ash.update!()

  # Every product whose price at the boundary decides something: the ended
  # season's holding and picks, and the starting season's picks that may be
  # picked. `USDC` may become the holding in any turn.
  defp priced(ended, scored, eligible) do
    Enum.uniq(
      [@usdc] ++
        if(ended, do: [ended.holding], else: []) ++
        Enum.map(scored, & &1.product) ++ MapSet.to_list(eligible)
    )
  end

  defp prices(products, boundary) do
    Enum.reduce_while(products, {:ok, %{}}, fn product, {:ok, prices} ->
      case Coinbase.price(product, boundary) do
        {:ok, price} -> {:cont, {:ok, Map.put(prices, product, price)}}
        {:error, _unread} = error -> {:halt, error}
      end
    end)
  end

  # A pick that came in after Coinbase was asked names a product it wasn't
  # asked about.
  defp asked_about(picks, asked) do
    if Enum.all?(picks, &(&1.product in asked)),
      do: {:ok, picks},
      else: {:error, :picks_changed}
  end

  defp latest(fleet_id) do
    Season
    |> Ash.Query.filter(fleet_id == ^fleet_id)
    |> Ash.Query.sort(number: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(actor: %System{})
  end

  defp ended(%Season{number: 1}), do: nil

  defp ended(%Season{fleet_id: fleet_id, number: number}) do
    Season
    |> Ash.Query.filter(fleet_id == ^fleet_id and number == ^(number - 1))
    |> Ash.read_one!(actor: %System{})
  end

  defp for_update(%Season{id: id}) do
    Season
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock("FOR UPDATE")
    |> Ash.read_one!(actor: %System{})
  end

  defp picks(%Season{id: season_id}) do
    SeasonPick
    |> Ash.Query.filter(season_id == ^season_id)
    |> Ash.Query.sort(lock_order: :asc)
    |> Ash.read!(actor: %System{})
  end

  # The ended season's picks that were given an open price at its start.
  defp locked_picks(%Season{id: season_id}) do
    SeasonPick
    |> Ash.Query.filter(season_id == ^season_id and not is_nil(open_price))
    |> Ash.Query.sort(lock_order: :asc)
    |> Ash.read!(actor: %System{})
  end
end
