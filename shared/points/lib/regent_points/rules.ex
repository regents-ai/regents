defmodule RegentPoints.Rules do
  @moduledoc """
  Finite proposed catalog. Nothing earns until the founder approves a rule,
  its source adapter is installed, and the program has an explicit start time.
  The program runs in three 30-day seasons from the start (Sean, 13 November
  2026); nothing done after the last one's end earns.
  Rates are pinned on intake; retries never apply today's pricing to old work.

  A rule's id never changes. A changed rule keeps its id and gets the next
  version, so what an account earned under the old version still counts
  against the new one; a new id is only for a new action.

  Each entry ends with `:listed`, shown on a Points page, or `:hidden`: it earns
  like any other rule, but no page lists it.
  """
  @unit 1_000_000
  @seasons 3
  @milestones [
    {"account.activated", 1, 25, "Account activated", :listed},
    {"social.x", 1, 10, "X account linked", :listed},
    {"social.github", 1, 10, "GitHub account linked", :listed},
    {"social.farcaster", 1, 10, "Farcaster account linked", :listed},
    {"agent.activated", 1, 25, "First paired agent", :listed},
    {"autolaunch.first_launch", 1, 25, "First Autolaunch launch", :listed},
    {"autolaunch.first_graduation", 2, 25, "First Autolaunch graduation", :listed},
    {"autolaunch.first_covered_call", 1, 25, "First Autolaunch covered call", :listed},
    {"autolaunch.token_staked", 1, 40, "Autolaunch token staked", :listed},
    {"keyfleet.first_membership", 2, 25, "First Keyfleet membership", :listed},
    {"keyfleet.first_authorized_agent", 2, 25, "First agent authorized on Keyfleet", :listed},
    {"keyfleet.first_message", 2, 25, "First Keyfleet message", :listed},
    {"keyfleet.first_vote", 2, 25, "First Keyfleet vote", :listed},
    {"keyfleet.integration.git", 1, 20, "Git used with Keyfleet", :listed},
    {"keyfleet.integration.marimo", 1, 20, "Marimo used with Keyfleet", :listed},
    {"keyfleet.integration.activegraph", 2, 20, "ActiveGraph used with Keyfleet", :listed},
    {"cloak.first_download", 1, 25, "First Cloak download", :listed},
    {"template.first_agent_note", 1, 10, "First note written by your agent", :hidden}
  ]
  @activity [
    {"autolaunch.auction_created", 1, 20, 1, "day", "Autolaunch auction created", :listed},
    {"autolaunch.auction_bid", 1, 20, 1, "day", "Autolaunch auction bid", :listed},
    {"autolaunch.token_traded", 1, 10, 1, "day", "Autolaunch token trade", :listed},
    {"keyfleet.key_bought", 1, 10, 5, "day", "Keyfleet key bought", :listed},
    {"patchbay.offer_bid_placed", 1, 5, 10, "day", "Patchbay Offer placed", :listed},
    {"patchbay.report_published", 1, 10, 1, "day", "Patchbay report published", :listed},
    {"patchbay.reply_published", 1, 5, 1, "day", "Patchbay reply published", :listed}
  ]

  @entries for({id, _version, _points, label, shown} <- @milestones, do: {id, label, shown}) ++
             for(
               {id, _version, _points, _count, _period, label, shown} <- @activity,
               do: {id, label, shown}
             )
  @labels Map.new(@entries, fn {id, label, _shown} -> {id, label} end)
  @hidden for {id, _label, :hidden} <- @entries, do: id

  # A Points page's groups, in order, each with the apps (an id's first segment) it holds.
  @groups [
    {"Account", ~w(account social agent)},
    {"Autolaunch", ~w(autolaunch)},
    {"Keyfleet", ~w(keyfleet)},
    {"Patchbay", ~w(patchbay)},
    {"Cloak", ~w(cloak)}
  ]
  @site_of Map.new(for {site, apps} <- @groups, app <- apps, do: {app, site})

  # One-time rules an account could already meet before the start: they earn at the
  # start, through RegentPoints.StartAwards, without the person doing anything.
  @start_rules ~w(account.activated social.x social.github social.farcaster agent.activated)

  @doc "The customer name of every catalog rule, including the source app."
  def label(id), do: Map.fetch!(@labels, id)

  def catalog do
    milestones =
      Enum.map(@milestones, fn {id, version, points, _label, _shown} ->
        rule(id, version, "milestone", points, 1, "lifetime")
      end)

    activity =
      Enum.map(@activity, fn {id, version, points, count, period, _label, _shown} ->
        rule(id, version, "activity", points, count, period)
      end)

    milestones ++ activity
  end

  def config, do: Application.get_all_env(:regent_points)
  def unit, do: @unit
  def program, do: Keyword.fetch!(config(), :program_id)
  def milestone_total, do: Enum.sum(Enum.map(@milestones, &elem(&1, 2)))
  def enabled?(id), do: id in Keyword.get(config(), :approved_rules, []) and adapter(id) != nil
  def adapter(id), do: config() |> Keyword.get(:adapters, %{}) |> Map.get(id)

  @doc """
  The rules this site earns: approved and given a source here. The approved
  list is the one switch.
  """
  def tracked, do: Enum.filter(catalog(), &enabled?(&1["id"]))

  @doc "The catalog rules a Points page shows: all but those the catalog marks `:hidden`."
  def listed, do: Enum.reject(catalog(), &(&1["id"] in @hidden))

  @doc """
  `listed/0` by the site each rule belongs to, in the page's order, as
  `[%{site: "Account", rules: [...]}, ...]`. The site comes from the id's first
  segment; every listed rule has one and every site has a listed rule.
  """
  def groups do
    rules = Enum.group_by(listed(), &Map.fetch!(@site_of, app(&1["id"])))
    for {site, _apps} <- @groups, do: %{site: site, rules: Map.fetch!(rules, site)}
  end

  @doc "The one-time rules whose state from before the start earns at the start."
  def start_rules, do: @start_rules
  def start_rule?(id), do: id in @start_rules

  @doc "The catalog rules that earn right now."
  def active,
    do: Enum.filter(catalog(), &match?({:ok, _}, snapshot(&1["id"], DateTime.utc_now())))

  def snapshot(id, at) do
    with %DateTime{} = start <- Keyword.get(config(), :starts_at),
         true <- DateTime.compare(at, start) != :lt,
         true <- DateTime.before?(at, ends_at()),
         true <- DateTime.compare(at, DateTime.utc_now()) != :gt,
         true <- enabled?(id),
         %{} = rule <- Enum.find(catalog(), &(&1["id"] == id)) do
      {:ok, Map.put(rule, "effective_at", DateTime.to_iso8601(start))}
    else
      _ -> {:error, :rule_not_active}
    end
  end

  @doc "Program period `n` as `{start, stop}`: 30-day periods counted from the start time."
  def period(n) do
    start = Keyword.fetch!(config(), :starts_at)
    {DateTime.add(start, (n - 1) * 30, :day), DateTime.add(start, n * 30, :day)}
  end

  @doc """
  How many seasons Points runs in: program periods 1 to this, one after the other
  from the start. After the last one's end nothing earns.
  """
  def season_count, do: @seasons

  @doc "When the last season ends, and with it all earning. Only once a start is set."
  def ends_at, do: elem(period(@seasons), 1)

  @doc "The program period `at` falls in. Every award is earned at or after the start."
  def period_of(at) do
    start = Keyword.fetch!(config(), :starts_at)
    div(DateTime.diff(at, start, :second), 30 * 86_400) + 1
  end

  @doc """
  The seasons that have ended by `now`, oldest first. Each gets one bonus tally;
  none comes after the last season.
  """
  def ended_periods(now) do
    case Keyword.get(config(), :starts_at) do
      %DateTime{} ->
        Enum.filter(1..@seasons, &(DateTime.compare(elem(period(&1), 1), now) != :gt))

      nil ->
        []
    end
  end

  def base_micro(%{"points" => points}) when is_integer(points), do: {:ok, points * @unit}
  def base_micro(_), do: {:error, :invalid_rule_snapshot}

  @doc """
  The daily limit a rule's points count against: every repeat action shares
  one, whoever acted, the person or any of their agents. One-time rules count
  against none.
  """
  def allowance_scope(%{"category" => "activity"}), do: "activity:account"
  def allowance_scope(_rule), do: nil

  def window("lifetime", _at), do: {~D[1970-01-01], nil}

  def window("day", at) do
    day = at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()
    {day, Date.add(day, 1)}
  end

  def daily_cap("activity:account"), do: 100 * @unit

  @doc "The apps the daily rules among `rules` come from."
  def daily_apps(rules) do
    for %{"category" => "activity", "id" => id} <- rules, uniq: true, do: app(id)
  end

  defp app(id), do: hd(String.split(id, "."))

  def activity_app?(app), do: app in daily_apps(catalog())

  @doc "What a rule's count is kept under: one count per action for the person and their agents."
  def count_scope(rule), do: rule["milestone_key"] || rule["id"]

  defp rule(id, version, category, points, count, period),
    do: %{
      "id" => id,
      "version" => version,
      "category" => category,
      "points" => points,
      "count" => count,
      "period" => period,
      "daily_caps_micro" => %{"activity:account" => daily_cap("activity:account")},
      "milestone_key" => if(category == "milestone", do: id)
    }
end
