defmodule RegentsWeb.Keyfleet.AgentTools.Seasons.Answer do
  @moduledoc """
  What a fleet's seasons (`Regents.Keyfleet.Seasons`) answer an agent, the same over
  its signed requests (`RegentsWeb.Keyfleet.AgentSeasonController`) and as the Claude
  connector's tools (`RegentsWeb.Keyfleet.AgentTools.Seasons`): the seasons now,
  locking or changing the agent's Key's pick, the settled seasons, one
  season's picks a page at a time, and the products open to picks. The
  settled seasons and their picks are the fleet's public record, answered
  alike to anyone, at the public addresses too
  (`RegentsWeb.Keyfleet.PublicSeasonsController`). Each answer is
  `{status, body, nil}`; `params` is the request's JSON, its body or query
  with the names in its address (`fleet_id`, and `number` at the public
  address of one season).

  Only an agent that is one of the fleet's members reads its seasons now and
  picks (`Regents.Keyfleet.Access`, `:seasons`); any other is answered
  `season_needs_key`. Who holds which Key decides those answers, down to
  whose pick a read carries, so none is given from ownership that isn't
  fresh. Keyfleet runs the game and keeps its record: it places no order and
  holds no money.
  """

  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Seasons
  alias Regents.Keyfleet.Seasons.CoinList
  alias Regents.Keyfleet.Seasons.Errors
  alias Regents.Keyfleet.Seasons.Season
  alias RegentsWeb.Keyfleet.{Refusal, SeasonJSON}

  # Picks a page holds, of the season under way in `show` and of any season
  # read on its own.
  @picks 100

  # A deployed fleet's turn opens its first season within ten minutes
  # (`Regents.Keyfleet.Seasons.Turns`).
  @no_season_yet "This fleet has no season yet. Its first opens for picks within ten minutes of " <>
                   "the fleet going live on Base; seasons_show shows it then."

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), term(), term()) :: {pos_integer(), map(), nil}
  def answer(:coins, _params, _actor, _waiter) do
    case CoinList.listing() do
      {:ok, products, read_at} -> {200, %{products: products, read_at: read_at}, nil}
      {:error, :unavailable} -> refusal(503, "coins_unread")
    end
  end

  def answer(:list, %{"fleet_id" => fleet_id} = params, _actor, _waiter) do
    if fleet_id in Fleets.open_fleet_ids(),
      do: record(fleet_id, Map.delete(params, "fleet_id")),
      else: refusal(404, "fleet_unknown")
  end

  # A settled season's picks, at the public address; the query is `after`
  # alone or nothing.
  def answer(:season, %{"fleet_id" => fleet_id} = params, _actor, _waiter) do
    with :ok <- known(fleet_id, Fleets.open_fleet_ids()),
         {:ok, number, place} <- picks_query(params) do
      if Seasons.settled_season(fleet_id, number),
        do: settled_picks(fleet_id, number, place),
        else: refusal(404, "season_unknown")
    end
  end

  # A season's picks for an agent: a settled one's for any, the one under
  # way's for a member.
  def answer(:picks, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    with :ok <- known(fleet_id, Fleets.catalog_ids()),
         {:ok, number, place} <- picks_query(params) do
      if Seasons.settled_season(fleet_id, number),
        do: settled_picks(fleet_id, number, place),
        else: running_picks(fleet_id, number, place, actor)
    end
  end

  def answer(op, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    cond do
      fleet_id not in Fleets.catalog_ids() -> refusal(404, "fleet_unknown")
      not Regents.Keyfleet.Chain.fresh?(fleet_id) -> refusal(503, "ownership_refreshing")
      true -> run(op, params, actor)
    end
  end

  # A member reads the season under way with its first page of picks, the
  # one taking picks with its own Key's pick alone, and the one settled as
  # the one under way started: a turn settling that one meanwhile changes
  # neither. A season past its end time is no longer under way, though its
  # turn hasn't settled it yet.
  defp run(:show, %{"fleet_id" => fleet_id}, actor) do
    with {:ok, locked} <- Seasons.running_season(fleet_id, actor: actor, authorize_with: :error),
         running = if(locked && Seasons.under_way?(locked), do: locked),
         {:ok, upcoming} <-
           Seasons.upcoming_season(fleet_id, actor: actor, authorize_with: :error),
         {:ok, picks} <- picks(running, actor),
         taking = if(upcoming && Seasons.taking_picks?(upcoming), do: upcoming),
         {:ok, mine} <- mine(taking, actor) do
      settled = running && Seasons.last_settled(fleet_id, running.number)
      {200, SeasonJSON.show(fleet_id, running, picks, taking, mine, settled), nil}
    else
      {:error, error} -> refuse(error)
    end
  end

  # A repeat of the pick the Key holds is answered with it, and the picker is
  # told nothing new was written.
  defp run(:pick, %{"fleet_id" => fleet_id} = params, actor) do
    with {:ok, %Season{} = season} <-
           Seasons.upcoming_season(fleet_id, actor: actor, authorize_with: :error),
         {:ok, pick} <-
           Seasons.pick(fleet_id, season.number, Map.take(params, ["product", "reason"]),
             actor: actor
           ) do
      status = if Ash.Resource.get_metadata(pick, :upsert_skipped), do: 200, else: 201
      {status, %{pick: SeasonJSON.pick(pick, season.number)}, nil}
    else
      {:ok, nil} -> refusal(409, "season_closed", @no_season_yet)
      {:error, error} -> refuse(error)
    end
  end

  defp record(fleet_id, query) do
    with {:ok, cursor} <- cursor(query, "before"),
         {:ok, before} <- SeasonJSON.opened(fleet_id, :seasons, cursor) do
      {seasons, more?} = Seasons.settled_page(fleet_id, before)
      {200, SeasonJSON.record(fleet_id, seasons, more?), nil}
    else
      :error -> refusal(400, "invalid_season_cursor")
    end
  end

  defp settled_picks(fleet_id, number, place) do
    page = Seasons.settled_picks_page(fleet_id, number, place, @picks)
    {200, SeasonJSON.picks(fleet_id, number, page), nil}
  end

  # Who holds which Key decides whether the season under way is read, so it
  # isn't read from ownership that isn't fresh.
  defp running_picks(fleet_id, number, place, actor) do
    if Regents.Keyfleet.Chain.fresh?(fleet_id) do
      with {:ok, %Season{number: ^number}} <-
             Seasons.running_season(fleet_id, actor: actor, authorize_with: :error),
           {:ok, page} <-
             Seasons.picks_page(fleet_id, number, place, @picks,
               actor: actor,
               authorize_with: :error
             ) do
        {200, SeasonJSON.picks(fleet_id, number, page), nil}
      else
        {:ok, _not_under_way} -> refusal(404, "season_unknown")
        {:error, error} -> refuse(error)
      end
    else
      refusal(503, "ownership_refreshing")
    end
  end

  defp known(fleet_id, fleet_ids),
    do: if(fleet_id in fleet_ids, do: :ok, else: refusal(404, "fleet_unknown"))

  # The season's `number`, from the address, names no season unless it is
  # one; `after` is the page's cursor, alone or not given, sealed for that
  # season's picks.
  defp picks_query(%{"fleet_id" => fleet_id} = params) do
    case number(params["number"]) do
      {:ok, number} ->
        with {:ok, cursor} <- cursor(Map.drop(params, ["fleet_id", "number"]), "after"),
             {:ok, place} <- SeasonJSON.opened(fleet_id, {:picks, number}, cursor) do
          {:ok, number, place}
        else
          :error -> refusal(400, "invalid_season_cursor")
        end

      nil ->
        refusal(404, "season_unknown")
    end
  end

  defp picks(nil, _actor), do: {:ok, {[], false}}

  defp picks(%Season{fleet_id: fleet_id, number: number}, actor),
    do: Seasons.picks_page(fleet_id, number, nil, @picks, actor: actor, authorize_with: :error)

  defp mine(nil, _actor), do: {:ok, nil}

  defp mine(%Season{fleet_id: fleet_id, number: number}, actor),
    do: Seasons.my_pick(fleet_id, number, actor: actor, authorize_with: :error)

  defp refuse(%Ash.Error.Forbidden{}), do: refusal(403, "season_needs_key")

  defp refuse(%Ash.Error.Framework{errors: [%Errors.ProductsUnreadError{}]}),
    do: refusal(503, "coins_unread")

  defp refuse(%Ash.Error.Invalid{errors: errors}) do
    cond do
      closed = Enum.find(errors, &is_struct(&1, Errors.PicksClosedError)) ->
        refusal(409, "season_closed", next_opens(closed.number))

      Enum.any?(errors, &is_struct(&1, Errors.ProductIneligibleError)) ->
        refusal(422, "product_not_open")

      reason = Enum.find(errors, &is_struct(&1, Errors.ReasonError)) ->
        refusal(
          422,
          "invalid_pick",
          Exception.message(reason) <> " Correct it, then send the request again."
        )

      true ->
        refusal(422, "invalid_pick")
    end
  end

  # A season's start locks it and opens the next for picks in one turn, a
  # minute after the boundary, or within ten minutes more when Coinbase
  # couldn't be read (`Regents.Keyfleet.Seasons.Turns`).
  defp next_opens(number) do
    "Season #{number} has started, so its picks are final. Season #{number + 1} opens for " <>
      "picks once that start is recorded, normally within a few minutes; seasons_show shows " <>
      "it then. Pick again for it."
  end

  # The query's one field, the cursor `name`, or none.
  defp cursor(query, _name) when map_size(query) == 0, do: {:ok, nil}

  defp cursor(query, name) when map_size(query) == 1 do
    case query do
      %{^name => cursor} when is_binary(cursor) -> {:ok, cursor}
      _other -> :error
    end
  end

  defp cursor(_query, _name), do: :error

  # A positive decimal at most the largest bigint, written without leading zeros.
  defp number(value) when is_binary(value) do
    if Regex.match?(~r/\A[1-9][0-9]{0,18}\z/, value) and
         String.to_integer(value) <= 9_223_372_036_854_775_807,
       do: {:ok, String.to_integer(value)}
  end

  defp number(_value), do: nil

  defp refusal(status, code), do: {status, Refusal.body(code), nil}
  defp refusal(status, code, hint), do: {status, Refusal.body(code, hint), nil}
end
