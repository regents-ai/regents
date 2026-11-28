defmodule RegentsWeb.AgentTools do
  @moduledoc """
  Core Regents hosted MCP tools exposed on the unified `/mcp` server: site
  health, public pages and docs, the product directory, Reading (research
  papers, Articles, literature), public Regent profiles, bundled product tool
  catalogs, SIWA connection help, and paired-agent account/claims/staking/
  Points/messaging tools.

  Together with `Regents.Account.Agents` (connected-app identity) and
  `Regents.Products.AccountOverview` (`regents_account_overview`), this gives
  `/mcp` complete parity with `priv/tool_manifest.json` (WebMCP) and
  `cli/regents/commands.json` (`regents protocol`).
  """

  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  resources do
    resource RegentsWeb.AgentTools.Public
    resource RegentsWeb.AgentTools.Account
  end

  tools do
    tool :regents_health, RegentsWeb.AgentTools.Public, :health do
      title("Read Regents service health")

      description "Check whether regents.sh, its database, migrations, and every folded product (Keyfleet, Autolaunch, Patchbay, Techtree) are answering."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_about, RegentsWeb.AgentTools.Public, :about do
      title("Read a Regents page")

      description "Read a regents.sh page as Markdown: about, contact, docs, any docs-* page, start, privacy, or terms."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_products, RegentsWeb.AgentTools.Public, :products do
      title("List Regents products")

      description "List the products in the Regents family: Keyfleet, Autolaunch, Patchbay, Techtree, and Cloak, with summaries, websites, GitHub repos, and pages on regents.sh."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_product, RegentsWeb.AgentTools.Public, :product do
      title("Read a product")

      description "Read everything one Regents product's page shows (patchbay, autolaunch, techtree, keyfleet, or cloak)."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_research_list, RegentsWeb.AgentTools.Public, :research_list do
      title("List research papers")

      description "List published Paper Pro Daily research papers, newest date first, ten per page. Pass after from pagination.next_cursor for subsequent pages."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_research_paper, RegentsWeb.AgentTools.Public, :research_paper do
      title("Read a research analysis")

      description "Read one published research paper with its complete analysis Markdown by id from regents_research_list."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_articles_list, RegentsWeb.AgentTools.Public, :articles_list do
      title("List Articles")

      description "List published Regents Labs Articles, newest date first, ten per page. Pass after from pagination.next_cursor for subsequent pages."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_article, RegentsWeb.AgentTools.Public, :article do
      title("Read an Article")

      description "Read one published Regents Labs Article with its full original Markdown by slug from regents_articles_list."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_literature, RegentsWeb.AgentTools.Public, :literature do
      title("Read AI and science fiction books")

      description "Read every book on AI & SCIFI with title, author, year, cover, Goodreads URL, themes, and editorial outlook scores."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_public_profile, RegentsWeb.AgentTools.Public, :public_profile do
      title("Read a public Regent profile")

      description "Read one public Regent profile by slug: display name, summary, picture, and public wallet address."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :list_regents_webmcp_tools, RegentsWeb.AgentTools.Public, :site_tools_regents do
      title("Read Regents tool catalog")

      description "Read the names, titles, and descriptions in the Regents tool manifest bundled with regents.sh."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :list_patchbay_webmcp_tools, RegentsWeb.AgentTools.Public, :site_tools_patchbay do
      title("Read Patchbay tool catalog")

      description "Read the names, titles, and descriptions in the Patchbay tool manifest bundled with regents.sh."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :list_autolaunch_webmcp_tools, RegentsWeb.AgentTools.Public, :site_tools_autolaunch do
      title("Read Autolaunch tool catalog")

      description "Read the names, titles, and descriptions in the Autolaunch tool manifest bundled with regents.sh."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :list_techtree_webmcp_tools, RegentsWeb.AgentTools.Public, :site_tools_techtree do
      title("Read Techtree tool catalog")

      description "Read the names, titles, and descriptions in the Techtree tool manifest bundled with regents.sh."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :list_keyfleet_webmcp_tools, RegentsWeb.AgentTools.Public, :site_tools_keyfleet do
      title("Read Keyfleet tool catalog")

      description "Read the names, titles, and descriptions in the Keyfleet tool manifest bundled with regents.sh."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :list_all_webmcp_tools, RegentsWeb.AgentTools.Public, :site_tools_all do
      title("Read Regents tool catalogs")

      description "Read the bundled tool manifests for Regents, Patchbay, Autolaunch, Techtree, and Keyfleet, plus SIWA setup."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :get_siwa_connection_help, RegentsWeb.AgentTools.Public, :siwa_help do
      title("How to connect an agent to siwa-server")

      description "How an agent connects to siwa-server, the shared sign-in every Regents site uses."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_agent_whoami, RegentsWeb.AgentTools.Account, :whoami do
      title("Check my agent identity and pairing")

      description "Check your SIWA identity, current pairing status, allowed actions, and next step without recording a check-in or awarding Points."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_agent_status, RegentsWeb.AgentTools.Account, :status do
      title("Check in as paired agent")

      description "Check in as a paired agent, update last_contact_at, and read the account you act for."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_account, RegentsWeb.AgentTools.Account, :account do
      title("Read the paired account")

      description "Read the paired owner account display name and ENS name together with your current pairing ID."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_claims, RegentsWeb.AgentTools.Account, :claims do
      title("Read the paired owner name claims")

      description "Read the paired owner's verified-wallet historical name claims. Send {} initially, then pass next as after."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :regents_stake_position, RegentsWeb.AgentTools.Account, :stake_position do
      title("Read the paired owner stake")

      description "Read the paired owner's primary-wallet REGENT staking position, shared staking totals, and available claims."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: true
      )
    end

    tool :account_points, RegentsWeb.AgentTools.Account, :points do
      title("Read Points")

      description "Read your person's Regent Points, today/yesterday totals, rank, open actions, daily limits, leaderboard, and recent entries."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :messages_leave, RegentsWeb.AgentTools.Account, :leave_message do
      title("Leave a message")

      description "Leave a private message for the Regents Labs team under a topic such as agents. Keep operation_id when retrying."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end
  end
end
