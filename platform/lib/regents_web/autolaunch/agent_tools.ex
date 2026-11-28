defmodule RegentsWeb.Autolaunch.AgentTools do
  @moduledoc """
  Autolaunch market reads, Exposure reads/preparations, paired-account draft
  tools, and non-custodial unsigned step builders on the unified `/mcp` server.
  Every tool reuses the exact same answers and refusals as the HTTP routes.
  """

  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  @manifest_files [
    "priv/autolaunch/tool_manifest.json",
    "priv/autolaunch/exposure_tools.json",
    "priv/autolaunch/agent_bids_tools.json",
    "priv/autolaunch/agent_robinhood_bids_tools.json",
    "priv/autolaunch/agent_launches_tools.json",
    "priv/autolaunch/agent_finish_tools.json",
    "priv/autolaunch/agent_stake_tools.json"
  ]

  for path <- @manifest_files do
    @external_resource Application.app_dir(:regents, path)
  end

  @browser_signing [
    " Signed: your browser host signs it with your own agent key, as regents browser does.",
    " Browser sign-in is not agent authority."
  ]
  @browser_tools (for file <- @manifest_files,
                      tool <-
                        :regents
                        |> Application.app_dir(file)
                        |> File.read!()
                        |> Jason.decode!()
                        |> Map.fetch!("tools"),
                      into: %{} do
                    words = String.replace(tool["description"], @browser_signing, "")
                    {tool["name"], %{tool | "description" => words}}
                  end)

  resources do
    resource RegentsWeb.Autolaunch.AgentTools.Market
    resource RegentsWeb.Autolaunch.AgentTools.Account
  end

  tools do
    tool :autolaunch_auctions, RegentsWeb.Autolaunch.AgentTools.Market, :auctions_answer do
      title(@browser_tools["autolaunch_auctions"]["title"])
      description @browser_tools["autolaunch_auctions"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_auction, RegentsWeb.Autolaunch.AgentTools.Market, :auction_answer do
      title(@browser_tools["autolaunch_auction"]["title"])
      description @browser_tools["autolaunch_auction"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_auction_counts, RegentsWeb.Autolaunch.AgentTools.Market, :counts_answer do
      title(@browser_tools["autolaunch_auction_counts"]["title"])
      description @browser_tools["autolaunch_auction_counts"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_tokens, RegentsWeb.Autolaunch.AgentTools.Market, :tokens_answer do
      title(@browser_tools["autolaunch_tokens"]["title"])
      description @browser_tools["autolaunch_tokens"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_token, RegentsWeb.Autolaunch.AgentTools.Market, :token_answer do
      title(@browser_tools["autolaunch_token"]["title"])
      description @browser_tools["autolaunch_token"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_treasury, RegentsWeb.Autolaunch.AgentTools.Market, :treasury_answer do
      title(@browser_tools["autolaunch_treasury"]["title"])
      description @browser_tools["autolaunch_treasury"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_bid_quote, RegentsWeb.Autolaunch.AgentTools.Market, :bid_quote_answer do
      title(@browser_tools["autolaunch_bid_quote"]["title"])
      description @browser_tools["autolaunch_bid_quote"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_after_hour_stocks_list,
         RegentsWeb.Autolaunch.AgentTools.Market,
         :after_hour_stocks_list do
      title(@browser_tools["autolaunch_after_hour_stocks_list"]["title"])
      description @browser_tools["autolaunch_after_hour_stocks_list"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: true)
    end

    tool :autolaunch_after_hour_stocks_series,
         RegentsWeb.Autolaunch.AgentTools.Market,
         :after_hour_stocks_series do
      title(@browser_tools["autolaunch_after_hour_stocks_series"]["title"])
      description @browser_tools["autolaunch_after_hour_stocks_series"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: true)
    end

    tool :autolaunch_revstake_draft,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :revstake_draft do
      title(@browser_tools["autolaunch_revstake_draft"]["title"])
      description @browser_tools["autolaunch_revstake_draft"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_revstake_draft_save,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :revstake_draft_save do
      title(@browser_tools["autolaunch_revstake_draft_save"]["title"])
      description @browser_tools["autolaunch_revstake_draft_save"]["description"]

      annotations(
        read_only_hint: false,
        destructive_hint: true,
        idempotent_hint: false,
        open_world_hint: false
      )
    end

    tool :autolaunch_memestock_draft,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :memestock_draft do
      title(@browser_tools["autolaunch_memestock_draft"]["title"])
      description @browser_tools["autolaunch_memestock_draft"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    end

    tool :autolaunch_memestock_draft_save,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :memestock_draft_save do
      title(@browser_tools["autolaunch_memestock_draft_save"]["title"])
      description @browser_tools["autolaunch_memestock_draft_save"]["description"]

      annotations(
        read_only_hint: false,
        destructive_hint: true,
        idempotent_hint: false,
        open_world_hint: false
      )
    end

    tool :autolaunch_my_positions, RegentsWeb.Autolaunch.AgentTools.Account, :my_positions do
      title(@browser_tools["autolaunch_my_positions"]["title"])
      description @browser_tools["autolaunch_my_positions"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: true)
    end

    tool :autolaunch_my_after_hour_stocks,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :my_after_hour_stocks do
      title(@browser_tools["autolaunch_my_after_hour_stocks"]["title"])
      description @browser_tools["autolaunch_my_after_hour_stocks"]["description"]
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: true)
    end

    tool :autolaunch_after_hour_stocks_prepare,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :after_hour_stocks_prepare do
      title(@browser_tools["autolaunch_after_hour_stocks_prepare"]["title"])
      description @browser_tools["autolaunch_after_hour_stocks_prepare"]["description"]
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: true)
    end

    tool :autolaunch_bid_prepare, RegentsWeb.Autolaunch.AgentTools.Account, :bid_prepare do
      title(@browser_tools["autolaunch_bid_prepare"]["title"])
      description @browser_tools["autolaunch_bid_prepare"]["description"]
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: true)
    end

    tool :autolaunch_bid_settlement_prepare,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :bid_settlement_prepare do
      title(@browser_tools["autolaunch_bid_settlement_prepare"]["title"])
      description @browser_tools["autolaunch_bid_settlement_prepare"]["description"]
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: true)
    end

    tool :autolaunch_robinhood_bid_prepare,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :robinhood_bid_prepare do
      title(@browser_tools["autolaunch_robinhood_bid_prepare"]["title"])
      description @browser_tools["autolaunch_robinhood_bid_prepare"]["description"]
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: true)
    end

    tool :autolaunch_robinhood_bid_settlement_prepare,
         RegentsWeb.Autolaunch.AgentTools.Account,
         :robinhood_bid_settlement_prepare do
      title(@browser_tools["autolaunch_robinhood_bid_settlement_prepare"]["title"])
      description @browser_tools["autolaunch_robinhood_bid_settlement_prepare"]["description"]
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: true)
    end

    tool :autolaunch_launch_prepare, RegentsWeb.Autolaunch.AgentTools.Account, :launch_prepare do
      title(@browser_tools["autolaunch_launch_prepare"]["title"])
      description @browser_tools["autolaunch_launch_prepare"]["description"]
      annotations(read_only_hint: false, destructive_hint: false, open_world_hint: true)
    end

    tool :autolaunch_finish_prepare, RegentsWeb.Autolaunch.AgentTools.Account, :finish_prepare do
      title(@browser_tools["autolaunch_finish_prepare"]["title"])
      description @browser_tools["autolaunch_finish_prepare"]["description"]
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: true)
    end

    tool :autolaunch_stake_prepare, RegentsWeb.Autolaunch.AgentTools.Account, :stake_prepare do
      title(@browser_tools["autolaunch_stake_prepare"]["title"])
      description @browser_tools["autolaunch_stake_prepare"]["description"]
      annotations(read_only_hint: true, destructive_hint: false, open_world_hint: true)
    end
  end
end
