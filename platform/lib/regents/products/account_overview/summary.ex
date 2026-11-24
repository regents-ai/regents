defmodule Regents.Products.AccountOverview.Summary do
  @moduledoc """
  Aggregates a single signed-in human's (or paired agent's owner's) current state
  across all Regents products using each product's domain code interfaces.
  """

  use Ash.Resource,
    domain: Regents.Products.AccountOverview,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentAgents.Person
  alias Regents.Account.Accounts
  alias Regents.Account.Actors.{Agent, Human}
  alias Regents.Autolaunch
  alias Regents.Keyfleet.{Fleets, Keys}
  alias Regents.Patchbay.{Forum, Members, Offers}
  alias Regents.Techtree.{ModelClimb, Projects, Watchdog}

  @preview_limit 6

  actions do
    action :summary, :map do
      description("""
      Reads the caller's unified account overview across Regents, Keyfleet,
      Autolaunch, Patchbay, and Techtree.
      """)

      run fn _input, %{actor: actor} -> build_summary(actor) end
    end
  end

  policies do
    policy action(:summary) do
      authorize_if Regents.Account.Accounts.Checks.HumanActor
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end

  defp build_summary(actor) do
    case resolve_account(actor) do
      {:ok, account, human_actor} ->
        keyfleet = read_keyfleet(human_actor)
        autolaunch = read_autolaunch(actor, human_actor, account)
        patchbay = read_patchbay(account)
        techtree = read_techtree(actor, human_actor, account)
        paired_agents = read_paired_agents(account)
        points = read_points(actor)

        overview = %{
          account: account_summary(account, actor, paired_agents, points),
          keyfleet: keyfleet,
          autolaunch: autolaunch,
          patchbay: patchbay,
          techtree: techtree,
          next_steps: build_next_steps(keyfleet, autolaunch, patchbay, techtree, paired_agents)
        }

        {:ok, overview}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_account(%Human{human_account_id: id} = human) do
    case Accounts.get_human_account(id, actor: human) do
      {:ok, %{} = account} -> {:ok, account, human}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_account(%Agent{human_account_id: id, pairing: %Human{} = human} = agent) do
    case Accounts.get_human_account(id, actor: agent) do
      {:ok, %{} = account} -> {:ok, account, human}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_account(_actor), do: {:error, :unauthorized}

  defp account_summary(account, actor, paired_agents, points) do
    base = %{
      id: account.id,
      display_name: account.display_name,
      ens_name: account.ens_name,
      wallet_address: account.wallet_address,
      wallet_count: length(linked_wallets(account)),
      paired_agents_count: paired_agents.count,
      paired_agents: paired_agents.items,
      points_balance: points
    }

    case actor do
      %Agent{pairing_id: pairing_id, wallet_address: agent_wallet} ->
        Map.merge(base, %{
          caller_role: "agent",
          pairing_id: pairing_id,
          agent_wallet: agent_wallet
        })

      %Human{} ->
        Map.put(base, :caller_role, "human")
    end
  end

  defp linked_wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp read_paired_agents(%{privy_user_id: privy_user_id}) when is_binary(privy_user_id) do
    person = %Person{privy_user_id: privy_user_id}

    case RegentAgents.list_my_agents(actor: person) do
      {:ok, agents} when is_list(agents) ->
        items =
          agents
          |> Enum.take(@preview_limit)
          |> Enum.map(fn agent ->
            %{
              id: agent.id,
              name: agent.name,
              harness: to_string(agent.harness),
              wallet: agent.wallet
            }
          end)

        %{count: length(agents), items: items}

      _ ->
        %{count: 0, items: []}
    end
  end

  defp read_paired_agents(_), do: %{count: 0, items: []}

  defp read_points(actor) do
    case RegentPoints.summary(actor: actor) do
      {:ok, %{balance_micro: micro}} when is_integer(micro) ->
        format_micro_points(micro)

      {:ok, %{balance: balance}} when is_binary(balance) ->
        balance

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp format_micro_points(micro) do
    sign = if micro < 0, do: "-", else: ""
    whole = div(abs(micro), 1_000_000)
    frac = rem(abs(micro), 1_000_000)

    if frac == 0 do
      sign <> Integer.to_string(whole)
    else
      trimmed =
        frac |> Integer.to_string() |> String.pad_leading(6, "0") |> String.trim_trailing("0")

      "#{sign}#{whole}.#{trimmed}"
    end
  end

  # --- Keyfleet ---

  defp read_keyfleet(%Human{wallet_addresses: wallets} = human_actor) do
    catalog_by_id = Map.new(Fleets.catalog(), &{&1.id, &1})

    case fetch_held_keys(wallets) do
      {:ok, held_keys} ->
        agent_keys = human_actor |> then(&Keys.agent_keys_of_person(actor: &1)) |> read_rows!()
        build_keyfleet_summary(held_keys, agent_keys, catalog_by_id)

      _ ->
        unavailable_keyfleet()
    end
  rescue
    _ -> unavailable_keyfleet()
  end

  defp fetch_held_keys([]), do: {:ok, []}
  defp fetch_held_keys(wallets), do: Keys.keys_held_everywhere(wallets)

  defp build_keyfleet_summary(held_keys, agent_keys, catalog_by_id) do
    agents_by_key = Enum.group_by(agent_keys, &{&1.fleet_id, &1.token_id})
    fleet_ids = held_keys |> Enum.map(& &1.fleet_id) |> Enum.uniq()
    has_keys = held_keys != []

    key_items =
      held_keys |> Enum.take(12) |> Enum.map(&keyfleet_item(&1, catalog_by_id, agents_by_key))

    %{
      status: "ready",
      state: if(has_keys, do: "has_keys", else: "no_keys"),
      has_keys: has_keys,
      keys_count: length(held_keys),
      fleets_count: length(fleet_ids),
      assigned_agents_count: length(agent_keys),
      keys: key_items,
      primary_action: keyfleet_primary_action(has_keys, key_items)
    }
  end

  defp keyfleet_item(key, catalog_by_id, agents_by_key) do
    fleet = Map.get(catalog_by_id, key.fleet_id)
    fleet_path = Map.get(fleet || %{}, :path) || "/keyfleet/app"
    fleet_name = Map.get(fleet || %{}, :name) || key.fleet_id

    %{
      fleet_id: key.fleet_id,
      fleet_name: fleet_name,
      fleet_path: fleet_path,
      token_id: key.token_id,
      key_path: "#{fleet_path}/keys/#{key.token_id}",
      owner_wallet: key.owner_wallet,
      assigned_agents_count:
        agents_by_key |> Map.get({key.fleet_id, key.token_id}, []) |> length()
    }
  end

  defp keyfleet_primary_action(true, [%{fleet_path: path} | _]),
    do: %{label: "Open fleet", path: path}

  defp keyfleet_primary_action(true, []), do: %{label: "Open fleet", path: "/keyfleet/app"}
  defp keyfleet_primary_action(false, _), do: %{label: "Browse fleets", path: "/keyfleet/app"}

  defp unavailable_keyfleet do
    %{
      status: "unavailable",
      state: "unavailable",
      has_keys: false,
      keys_count: 0,
      fleets_count: 0,
      assigned_agents_count: 0,
      keys: [],
      primary_action: %{label: "Open Keyfleet", path: "/keyfleet/app"}
    }
  end

  # --- Autolaunch ---

  defp read_autolaunch(actor, %Human{wallet_addresses: wallets} = human_actor, account) do
    bids = fetch_wallet_bids(wallets, human_actor)
    to_settle = fetch_wallet_bids_to_settle(wallets, human_actor)
    auctions = Autolaunch.list_my_auctions!(actor: actor, query: [limit: @preview_limit])
    auctions_count = Autolaunch.count_my_auctions!(actor: actor)
    drafts_count = count_autolaunch_drafts(human_actor)
    has_portfolio = bids != [] or auctions != [] or drafts_count > 0

    %{
      status: "ready",
      state: if(has_portfolio, do: "has_portfolio", else: "no_portfolio"),
      has_portfolio: has_portfolio,
      has_wallet: present_string?(account.wallet_address),
      bids_count: length(bids),
      bids_to_settle_count: length(to_settle),
      auctions_created_count: auctions_count,
      drafts_count: drafts_count,
      recent_bids: bids |> Enum.take(@preview_limit) |> Enum.map(&autolaunch_bid_item/1),
      created_auctions:
        auctions |> Enum.take(@preview_limit) |> Enum.map(&autolaunch_auction_item/1),
      primary_action: autolaunch_primary_action(has_portfolio)
    }
  rescue
    _ -> unavailable_autolaunch()
  end

  defp fetch_wallet_bids([], _human_actor), do: []

  defp fetch_wallet_bids(wallets, human_actor) do
    wallets |> Autolaunch.list_wallet_bid_positions(actor: human_actor) |> read_rows!()
  end

  defp fetch_wallet_bids_to_settle([], _human_actor), do: []

  defp fetch_wallet_bids_to_settle(wallets, human_actor) do
    wallets |> Autolaunch.list_wallet_bids_to_settle(actor: human_actor) |> read_rows!()
  end

  defp count_autolaunch_drafts(human_actor) do
    agent_drafts =
      human_actor |> then(&Autolaunch.list_my_launch_drafts(actor: &1)) |> read_rows!()

    stocks_count =
      case Autolaunch.get_my_stocks_launch_draft(actor: human_actor) do
        {:ok, %{}} -> 1
        {:ok, nil} -> 0
        {:error, error} -> raise Ash.Error.to_error_class(error)
      end

    length(agent_drafts) + stocks_count
  end

  defp autolaunch_bid_item(bid) do
    auction = bid.auction || %{}

    %{
      id: bid.id,
      bid_id: bid.bid_id,
      status: to_string(bid.status),
      amount: to_string(bid.amount),
      token_symbol: Map.get(auction, :token_symbol),
      auction_title: Map.get(auction, :title),
      path: "/autolaunch/portfolio/bids/#{bid.id}"
    }
  end

  defp autolaunch_auction_item(auction) do
    %{
      id: auction.id,
      title: auction.title,
      token_symbol: auction.token_symbol,
      state: to_string(auction.state),
      kind: to_string(auction.kind),
      path: auction_path(auction)
    }
  end

  defp autolaunch_primary_action(true),
    do: %{label: "Open portfolio", path: "/autolaunch/portfolio"}

  defp autolaunch_primary_action(false),
    do: %{label: "Browse auctions", path: "/autolaunch/auctions"}

  defp unavailable_autolaunch do
    %{
      status: "unavailable",
      state: "unavailable",
      has_portfolio: false,
      has_wallet: false,
      bids_count: 0,
      bids_to_settle_count: 0,
      auctions_created_count: 0,
      drafts_count: 0,
      recent_bids: [],
      created_auctions: [],
      primary_action: %{label: "Open Autolaunch", path: "/autolaunch/app"}
    }
  end

  defp auction_path(%{token_symbol: symbol, path_tail: tail})
       when is_binary(symbol) and symbol != "" and is_binary(tail) and tail != "" do
    "/autolaunch/auctions/#{URI.encode_www_form(symbol)}/#{tail}"
  end

  defp auction_path(_), do: "/autolaunch/auctions"

  # --- Patchbay ---

  defp read_patchbay(account) do
    offers_enabled = Offers.enabled?()
    profile = fetch_patchbay_profile(account.privy_user_id)
    profile_id = profile && profile.id

    posts =
      Forum.list_reports_for_account!(profile_id, account.id, load: [:solved], query: [limit: 5])

    {posts_count, replies_count} = Forum.account_counts!(profile_id, account.id)
    campaigns = fetch_patchbay_campaigns(offers_enabled, profile)
    active_leases_count = Offers.Board.count_market_leases(campaigns)
    has_posts = posts_count > 0 or replies_count > 0
    has_agent_offers = campaigns != [] or active_leases_count > 0
    profile_public_id = extract_public_id(profile)
    profile_path = if profile_public_id, do: "/patchbay/agents/#{profile_public_id}", else: nil

    %{
      status: "ready",
      state: patchbay_state(has_posts, has_agent_offers),
      has_posts: has_posts,
      has_agent_offers: has_agent_offers,
      has_activity: has_posts or has_agent_offers,
      offers_enabled: offers_enabled,
      profile_public_id: profile_public_id,
      profile_path: profile_path,
      posts_count: posts_count,
      replies_count: replies_count,
      campaigns_count: length(campaigns),
      active_leases_count: active_leases_count,
      recent_posts: posts |> Enum.take(5) |> Enum.map(&patchbay_post_item/1),
      campaigns: campaigns |> Enum.take(5) |> Enum.map(&patchbay_campaign_item/1),
      primary_action:
        patchbay_primary_action(has_agent_offers, offers_enabled, has_posts, profile_path)
    }
  rescue
    _ -> unavailable_patchbay()
  end

  defp fetch_patchbay_profile(privy_user_id) when is_binary(privy_user_id) do
    case Members.get_profile_by_privy_user_id(privy_user_id) do
      {:ok, member} -> member
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  defp fetch_patchbay_profile(_), do: nil

  defp fetch_patchbay_campaigns(true, %{} = profile) do
    Offers.my_campaigns(actor: profile, load: [:review]) |> read_rows!()
  end

  defp fetch_patchbay_campaigns(_, _), do: []

  defp patchbay_state(true, true), do: "has_posts_and_offers"
  defp patchbay_state(true, false), do: "has_posts"
  defp patchbay_state(false, true), do: "has_agent_offers"
  defp patchbay_state(false, false), do: "empty"

  defp patchbay_post_item(report) do
    %{
      id: report.id,
      title: report.title,
      kind: to_string(report.kind),
      solved: report.solved,
      path: "/patchbay/posts/#{report.id}"
    }
  end

  defp patchbay_campaign_item(campaign) do
    %{
      id: campaign.id,
      campaign_id: campaign.campaign_id,
      title: campaign.title,
      review: to_string(campaign.review || :waiting),
      leases_count: length(List.wrap(campaign.leases)),
      path: "/patchbay/offers"
    }
  end

  defp extract_public_id(%{public_id: id}) when is_binary(id) and id != "", do: id
  defp extract_public_id(_), do: nil

  defp patchbay_primary_action(true, true, _has_posts, _profile_path),
    do: %{label: "Manage agent offers", path: "/patchbay/offers"}

  defp patchbay_primary_action(_has_offers, _offers_enabled, true, profile_path)
       when is_binary(profile_path),
       do: %{label: "View your posts", path: profile_path}

  defp patchbay_primary_action(_, _, _, _),
    do: %{label: "Open Patchbay forum", path: "/patchbay/forum"}

  defp unavailable_patchbay do
    %{
      status: "unavailable",
      state: "unavailable",
      has_posts: false,
      has_agent_offers: false,
      has_activity: false,
      offers_enabled: Offers.enabled?(),
      profile_public_id: nil,
      profile_path: nil,
      posts_count: 0,
      replies_count: 0,
      campaigns_count: 0,
      active_leases_count: 0,
      recent_posts: [],
      campaigns: [],
      primary_action: %{label: "Open Patchbay", path: "/patchbay/forum"}
    }
  end

  # --- Techtree ---

  defp read_techtree(actor, human_actor, account) do
    projects = Projects.list_my_projects(actor: actor) |> read_rows!()
    watchdog_hosts = Watchdog.list_my_hosts(actor: human_actor) |> read_rows!()
    model_climb_reports = fetch_model_climb_reports(account.privy_user_id)
    has_projects = projects != []

    %{
      status: "ready",
      state: if(has_projects, do: "has_projects", else: "no_projects"),
      has_projects: has_projects,
      projects_count: length(projects),
      watchdog_hosts_count: length(watchdog_hosts),
      model_climb_reports_count: length(model_climb_reports),
      projects: projects |> Enum.take(@preview_limit) |> Enum.map(&techtree_project_item/1),
      primary_action: techtree_primary_action(has_projects)
    }
  rescue
    _ -> unavailable_techtree()
  end

  defp fetch_model_climb_reports(privy_user_id) when is_binary(privy_user_id) do
    ModelClimb.list_my_reports(actor: %{privy_user_id: privy_user_id}) |> read_rows!()
  end

  defp fetch_model_climb_reports(_), do: []

  defp techtree_project_item(project) do
    %{
      id: project.id,
      title: project.title,
      line: to_string(project.line),
      verdict: project.verdict && to_string(project.verdict),
      delivered_at: project.delivered_at && DateTime.to_iso8601(project.delivered_at),
      path: "/techtree/account/projects/#{project.id}"
    }
  end

  defp techtree_primary_action(true),
    do: %{label: "Open projects", path: "/techtree/account/projects"}

  defp techtree_primary_action(false), do: %{label: "Explore Techtree", path: "/techtree/app"}

  defp unavailable_techtree do
    %{
      status: "unavailable",
      state: "unavailable",
      has_projects: false,
      projects_count: 0,
      watchdog_hosts_count: 0,
      model_climb_reports_count: 0,
      projects: [],
      primary_action: %{label: "Open Techtree", path: "/techtree/app"}
    }
  end

  defp read_rows!({:ok, rows}) when is_list(rows), do: rows
  defp read_rows!({:error, error}), do: raise(Ash.Error.to_error_class(error))

  defp present_string?(value), do: is_binary(value) and value != ""

  defp build_next_steps(keyfleet, autolaunch, patchbay, techtree, paired_agents) do
    []
    |> maybe_step(
      paired_agents.count == 0,
      "agents",
      "Pair an agent so it can act for your account across Regents.",
      "/account/agents"
    )
    |> maybe_step(
      keyfleet.status == "ready" and not keyfleet.has_keys,
      "keyfleet",
      "No Keyfleet Keys held yet. Browse fleets to get a Key and unlock member workspaces.",
      "/keyfleet/app"
    )
    |> maybe_step(
      autolaunch.status == "ready" and autolaunch.bids_to_settle_count > 0,
      "autolaunch",
      "You have #{autolaunch.bids_to_settle_count} ended Autolaunch bid(s) ready to settle or claim.",
      "/autolaunch/portfolio"
    )
    |> maybe_step(
      autolaunch.status == "ready" and not autolaunch.has_portfolio,
      "autolaunch",
      "No Autolaunch portfolio yet. Explore live auctions or draft a launch.",
      "/autolaunch/auctions"
    )
    |> maybe_step(
      patchbay.status == "ready" and not patchbay.has_posts and not patchbay.has_agent_offers,
      "patchbay",
      "No Patchbay posts or agent offers yet. Ask a question on the forum or browse listed sites.",
      "/patchbay/forum"
    )
    |> maybe_step(
      techtree.status == "ready" and not techtree.has_projects,
      "techtree",
      "No Techtree projects delivered yet. Browse Skills, Evals, Environments, and Models.",
      "/techtree/app"
    )
    |> Enum.reverse()
  end

  defp maybe_step(steps, false, _product, _message, _path), do: steps

  defp maybe_step(steps, true, product, message, path),
    do: [%{product: product, message: message, path: path} | steps]
end
