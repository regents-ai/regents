defmodule Regents.Keyfleet.Seasons do
  @moduledoc """
  A deployed fleet's seasons: back to back, three hours each, on the UTC
  boundaries 00:00, 03:00 … 21:00, numbered from 1 for each fleet.

  While one season runs, the fleet's members lock a pick for the next: one
  Coinbase product quoted in US dollars (`SOL-USD`), or `USDC`, with a short
  reason if they give one. A member is anyone polls count as one
  (`Regents.Keyfleet.Polls.voter/2`), and each Key has one pick a season. A pick may
  change until its season starts; a change takes the newest place in the
  order picks were locked. Until the season starts a pick is read only by
  its own Key's holder and that Key's agents; from the start every member
  reads every pick. Anyone reads the season under way, its holding, captain
  and prices, but not its picks (`running_season/2`). Once a season is
  settled it is public record, its picks with it: anyone reads it
  (`settled_page/2`, `settled_picks_page/4`), its Keys by number. No read
  answers more than a page, however many Keys pick.

  When a season ends each pick is scored by what its product did over the
  season, and the best one may take the crown: the fleet's holding for the
  next season becomes its product and its Key becomes captain
  (`Regents.Keyfleet.Seasons.Rules`). A fleet's first season holds `USDC` with no
  captain.

  Keyfleet never holds or moves anyone's money and never touches a Coinbase
  account: the holding is a score, read from Coinbase's public market data
  (`Regents.Keyfleet.Seasons.Coinbase`).

  A season turning is announced on `topic/1` as "seasons_changed", and each
  pick locked or changed on its season's `season_topic/1` as
  "season_changed", with nothing else, so pages read them again.
  """
  use Ash.Domain

  alias Regents.Keyfleet.Seasons.{Season, SeasonPick}

  @season_hours 3
  # Settled seasons a page of the public record holds.
  @page 20

  resources do
    resource Regents.Keyfleet.Seasons.Season do
      define :list_seasons, action: :in_fleet, args: [:fleet_id]
      define :get_season, action: :numbered, args: [:fleet_id, :number], not_found_error?: false
      define :upcoming_season, action: :upcoming, args: [:fleet_id], not_found_error?: false
      define :running_season, action: :running, args: [:fleet_id], not_found_error?: false
    end

    resource Regents.Keyfleet.Seasons.SeasonPick do
      define :pick, action: :pick, args: [:fleet_id, :number]
      define :my_pick, action: :mine, args: [:fleet_id, :number], not_found_error?: false
    end
  end

  @doc "Where a fleet announces a season turning, as `\"seasons_changed\"`."
  def topic(fleet_id), do: "keyfleet:seasons:#{fleet_id}"

  @doc "Where a season announces a pick locked or changed, as `\"season_changed\"`."
  def season_topic(season_id), do: "keyfleet:season:#{season_id}"

  @doc "The boundary at or before `at`: the start of the season running then."
  @spec boundary(DateTime.t()) :: DateTime.t()
  def boundary(%DateTime{time_zone: "Etc/UTC", hour: hour} = at),
    do: %{at | hour: hour - rem(hour, @season_hours), minute: 0, second: 0, microsecond: {0, 6}}

  @doc "When a season starting at `starts_at` ends, and the next one starts."
  @spec ends_at(DateTime.t()) :: DateTime.t()
  def ends_at(%DateTime{} = starts_at), do: DateTime.add(starts_at, @season_hours, :hour)

  @doc "How many hours a season lasts."
  @spec season_hours() :: pos_integer()
  def season_hours, do: @season_hours

  @doc "Whether `season` still takes picks at `now`: its turn hasn't locked it, and it hasn't started."
  @spec taking_picks?(Season.t(), DateTime.t()) :: boolean()
  def taking_picks?(season, now \\ DateTime.utc_now())

  def taking_picks?(%Season{locked_at: nil, starts_at: starts_at}, now),
    do: DateTime.after?(starts_at, now)

  def taking_picks?(%Season{}, _now), do: false

  @doc """
  Whether the season its turn locked (`running_season/2`) is still under way
  at `now`: its end time hasn't come. From then until its turn settles it,
  normally a minute later, it has ended and isn't settled yet.
  """
  @spec under_way?(Season.t(), DateTime.t()) :: boolean()
  def under_way?(%Season{ends_at: ends_at}, now \\ DateTime.utc_now()),
    do: DateTime.after?(ends_at, now)

  @doc """
  A page of the fleet's settled seasons, newest first, each with how many
  Keys picked and its best pick: the newest, or those numbered below
  `before`. Answers `{seasons, more?}`, `more?` saying older ones follow.
  """
  @spec settled_page(String.t(), pos_integer() | nil) :: {[Season.t()], boolean()}
  def settled_page(fleet_id, before) do
    Season
    |> Ash.Query.for_read(:settled, %{fleet_id: fleet_id, before: before})
    |> Ash.Query.limit(@page + 1)
    |> Ash.read!()
    |> split(@page)
  end

  @doc """
  The fleet's newest settled season numbered below `before`, with how many
  Keys picked and its best pick, or nil when none is. Named by the season
  under way, it is the one settled as that one started, even if a turn has
  settled that one since.
  """
  @spec last_settled(String.t(), pos_integer() | nil) :: Season.t() | nil
  def last_settled(fleet_id, before) do
    Season
    |> Ash.Query.for_read(:settled, %{fleet_id: fleet_id, before: before})
    |> Ash.Query.limit(1)
    |> Ash.read_one!()
  end

  @doc "The fleet's settled season numbered `number`, for anyone, or nil when it has none."
  @spec settled_season(String.t(), pos_integer()) :: Season.t() | nil
  def settled_season(fleet_id, number) do
    Season
    |> Ash.Query.for_read(:settled, %{fleet_id: fleet_id, number: number})
    |> Ash.read_one!()
  end

  @doc """
  Up to `size` picks of the fleet's season numbered `number` once it has
  started, in the order they were locked, after the one locked at `place`
  when it is given, as `actor` in `opts` may read them: a member reads the
  season under way's (`:in_season`). Answers `{:ok, {picks, more?}}`, or the
  read's error; `next_after/1` names the page after it.
  """
  @spec picks_page(String.t(), pos_integer(), pos_integer() | nil, pos_integer(), keyword()) ::
          {:ok, {[SeasonPick.t()], boolean()}} | {:error, term()}
  def picks_page(fleet_id, number, place, size, opts) do
    SeasonPick
    |> Ash.Query.for_read(
      :in_season,
      %{fleet_id: fleet_id, number: number, after: place},
      Keyword.take(opts, [:actor])
    )
    |> Ash.Query.limit(size + 1)
    |> Ash.read(opts)
    |> case do
      {:ok, picks} -> {:ok, split(picks, size)}
      {:error, _error} = error -> error
    end
  end

  @doc "The same of a settled season, for anyone: its public record's (`:in_settled_season`)."
  @spec settled_picks_page(String.t(), pos_integer(), pos_integer() | nil, pos_integer()) ::
          {[SeasonPick.t()], boolean()}
  def settled_picks_page(fleet_id, number, place, size) do
    SeasonPick
    |> Ash.Query.for_read(:in_settled_season, %{fleet_id: fleet_id, number: number, after: place})
    |> Ash.Query.limit(size + 1)
    |> Ash.read!()
    |> split(size)
  end

  @doc "The `after` that reads the picks following `picks`, or nil when none follow."
  @spec next_after({[SeasonPick.t()], boolean()}) :: pos_integer() | nil
  def next_after({picks, true}), do: List.last(picks).lock_order
  def next_after({_picks, false}), do: nil

  defp split(records, size) do
    {page, rest} = Enum.split(records, size)
    {page, rest != []}
  end
end
