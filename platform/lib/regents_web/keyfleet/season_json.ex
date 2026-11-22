defmodule RegentsWeb.Keyfleet.SeasonJSON do
  @moduledoc """
  A fleet's seasons as the agent API and the public record answer them
  (`RegentsWeb.Keyfleet.AgentTools.Seasons.Answer`). Keys are named by number, never
  by wallet, and prices and results are decimal strings, as Coinbase sent
  the prices. No answer carries more than a page of picks: a season's picks
  are read on their own (`picks/3`).

  A page's cursor is one string an agent hands back unchanged: the place it
  names is sealed with the site's secret (`Phoenix.Token`), with the fleet
  and the list it continues, so it can't be forged and tells nothing of
  where a pick stands among other fleets' writes (`opened/3`). It never
  expires: the record it pages never changes.
  """

  alias Regents.Keyfleet.Seasons
  alias Regents.Keyfleet.Seasons.{Coinbase, Rules}

  @salt "season cursor"

  @doc """
  The fleet's seasons as a member reads them now: the season under way with
  how many Keys picked and the first page of its picks, the season taking
  picks with the caller's own pick and how many Keys have locked one, the
  season settled last, and the rules.
  """
  def show(fleet_id, running, running_picks, taking_picks, my_pick, settled) do
    %{
      fleet_id: fleet_id,
      running: running && running(running, running_picks),
      taking_picks: taking_picks && taking_picks(taking_picks, my_pick),
      last_settled: settled && last_settled(settled, running),
      rules: %{
        season_hours: Seasons.season_hours(),
        switching_margin: decimal(Rules.switching_margin()),
        volume_floor_usd: decimal(Coinbase.volume_floor())
      }
    }
  end

  @doc "A page of the fleet's settled seasons, its public record."
  def record(fleet_id, seasons, more?) do
    %{
      fleet_id: fleet_id,
      seasons: Enum.map(seasons, &settled/1),
      next_before: if(more?, do: sealed(fleet_id, :seasons, List.last(seasons).number)),
      has_more: more?
    }
  end

  @doc """
  The place a cursor names in the fleet's `list`, `:seasons` for its settled
  seasons or `{:picks, number}` for one season's picks: `{:ok, nil}` for no
  cursor, `{:ok, place}`, or `:error` for any string this site didn't seal
  for that list.
  """
  def opened(_fleet_id, _list, nil), do: {:ok, nil}

  def opened(fleet_id, list, cursor) when is_binary(cursor) do
    case Phoenix.Token.decrypt(RegentsWeb.Endpoint, @salt, cursor, max_age: :infinity) do
      {:ok, {^fleet_id, ^list, place}} -> {:ok, place}
      _other -> :error
    end
  end

  def opened(_fleet_id, _list, _cursor), do: :error

  @doc """
  A page of one season's picks, in the order they were locked: a season
  under way's have no close price or result yet.
  """
  def picks(fleet_id, number, {picks, more?} = page) do
    %{
      fleet_id: fleet_id,
      season: number,
      picks:
        Enum.map(
          picks,
          &Map.merge(running_pick(&1), %{
            close_price: decimal(&1.close_price),
            result: decimal(&1.result)
          })
        ),
      next_after: next_after(fleet_id, number, page),
      has_more: more?
    }
  end

  @doc "A Key's own pick for a season taking picks."
  def pick(pick, number) do
    %{
      season: number,
      key: pick.token_id,
      product: pick.product,
      reason: pick.reason,
      picked_at: pick.picked_at
    }
  end

  defp running(season, {picks, _more?} = page) do
    %{
      number: season.number,
      starts_at: season.starts_at,
      ends_at: season.ends_at,
      holding: season.holding,
      captain_key: season.captain_key,
      holding_open_price: decimal(season.holding_open_price),
      pick_count: season.keys_locked,
      picks: Enum.map(picks, &running_pick/1),
      next_after: next_after(season.fleet_id, season.number, page)
    }
  end

  defp running_pick(pick) do
    %{
      key: pick.token_id,
      product: pick.product,
      reason: pick.reason,
      open_price: decimal(pick.open_price),
      void: pick.void
    }
  end

  defp taking_picks(season, my_pick) do
    %{
      number: season.number,
      starts_at: season.starts_at,
      my_pick: my_pick && pick(my_pick, season.number),
      keys_locked: season.keys_locked
    }
  end

  # The season after the one settled last is the one under way: a turn
  # settles one and locks the next together.
  defp last_settled(settled, running) do
    %{
      number: settled.number,
      holding: settled.holding,
      holding_result: decimal(settled.holding_result),
      best_pick: best_pick(settled.best_pick),
      crown_changed: running.holding != settled.holding
    }
  end

  defp settled(season) do
    %{
      number: season.number,
      starts_at: season.starts_at,
      ends_at: season.ends_at,
      holding: season.holding,
      captain_key: season.captain_key,
      holding_open_price: decimal(season.holding_open_price),
      holding_close_price: decimal(season.holding_close_price),
      holding_result: decimal(season.holding_result),
      pick_count: season.keys_locked,
      best_pick: best_pick(season.best_pick)
    }
  end

  defp best_pick(nil), do: nil

  defp best_pick(pick),
    do: %{key: pick.token_id, product: pick.product, result: decimal(pick.result)}

  defp next_after(fleet_id, number, page) do
    case Seasons.next_after(page) do
      nil -> nil
      place -> sealed(fleet_id, {:picks, number}, place)
    end
  end

  defp sealed(fleet_id, list, place),
    do: Phoenix.Token.encrypt(RegentsWeb.Endpoint, @salt, {fleet_id, list, place})

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = value), do: Decimal.to_string(value, :normal)
end
