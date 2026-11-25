defmodule RegentsWeb.Autolaunch.AgentTools do
  @moduledoc """
  Autolaunch market reads and paired-account draft tools on the unified
  `/mcp` server. The tools reuse the signed HTTP and public market answers.
  """

  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  @manifest_path Application.app_dir(:regents, "priv/autolaunch/tool_manifest.json")
  @external_resource @manifest_path

  @browser_signing [
    " Signed: your browser host signs it with your own agent key, as regents browser does.",
    " Browser sign-in is not agent authority."
  ]
  @browser_tools (for tool <-
                        @manifest_path |> File.read!() |> Jason.decode!() |> Map.fetch!("tools"),
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
  end
end
