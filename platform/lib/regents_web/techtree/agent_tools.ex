defmodule RegentsWeb.Techtree.AgentTools do
  @moduledoc """
  Techtree's hosted MCP tools exposed on the unified `/mcp` server: reading the
  active catalog and CLI bootstrap contract, inspecting a Climb's fixed task
  contract, listing and reading published Results, reading the Agent Wallet
  Bench score grids, and listing published public Skill comparisons.
  """

  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  resources do
    resource RegentsWeb.Techtree.AgentTools.Public
    resource RegentsWeb.Techtree.AgentTools.Account
  end

  tools do
    tool :techtree_catalog, RegentsWeb.Techtree.AgentTools.Public, :catalog do
      title("Read Techtree catalog")

      description "Read the active Techtree catalog of published Climbs and Skills."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_bootstrap, RegentsWeb.Techtree.AgentTools.Public, :bootstrap do
      title("Read Techtree bootstrap")

      description "Read the active Techtree release's CLI bootstrap and install metadata."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_climb, RegentsWeb.Techtree.AgentTools.Public, :climb do
      title("Read a Techtree Climb")

      description "Read the fixed task contract, data policy, and linked object URLs for one Techtree Climb by slug."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_publications, RegentsWeb.Techtree.AgentTools.Public, :publications do
      title("List Techtree published Results")

      description "List published Techtree evaluation Results, newest first, with optional limit and before_sequence cursor."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_publication_show, RegentsWeb.Techtree.AgentTools.Public, :publication_show do
      title("Read one Techtree Result")

      description "Read one published Techtree Result's verified projection, per-task scores, and countersigned receipt by bundle digest."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_skill, RegentsWeb.Techtree.AgentTools.Public, :skill do
      title("Read a published Techtree Skill")

      description "Read a published Techtree Skill's files and standing Results by root digest."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_wallet_bench, RegentsWeb.Techtree.AgentTools.Public, :wallet_bench do
      title("Read Techtree Wallet Bench")

      description "Read the live Agent Wallet Bench score grids comparing coding agents across wallet tools."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_train_comparisons, RegentsWeb.Techtree.AgentTools.Public, :train_comparisons do
      title("List Techtree Train comparisons")

      description "List Techtree's published public Skill comparison demonstrations, verdicts, and report URLs."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_train_report, RegentsWeb.Techtree.AgentTools.Public, :train_report do
      title("Read a Techtree Train report")

      description "Read one Techtree Skill comparison's exact committed per-case JSON report by slug."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_account_projects, RegentsWeb.Techtree.AgentTools.Account, :account_projects do
      title("List delivered Techtree projects")

      description "List Techtree projects delivered to your paired person, newest first (requires paired SIWA agent)."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_account_project, RegentsWeb.Techtree.AgentTools.Account, :account_project do
      title("Read one delivered Techtree project")

      description "Read one delivered Techtree project with its structured manifest, rerun_test receipt, report, and package metadata (requires paired SIWA agent)."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_model_climb_list, RegentsWeb.Techtree.AgentTools.Account, :model_climb_list do
      title("List private Model Climb reports")

      description "List private Model Climb proof reports stored for your paired person (requires paired SIWA agent)."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_model_climb_show, RegentsWeb.Techtree.AgentTools.Account, :model_climb_show do
      title("Read one private Model Climb report")

      description "Read one private Model Climb proof report by digest for your paired person (requires paired SIWA agent)."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_orders_list, RegentsWeb.Techtree.AgentTools.Account, :orders_list do
      title("List Techtree Uplift Factory orders")

      description "List Uplift Factory orders belonging to your paired person, newest first (requires paired SIWA agent)."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_orders_show, RegentsWeb.Techtree.AgentTools.Account, :orders_show do
      title("Read one Techtree Uplift Factory order")

      description "Read one Uplift Factory order's state, quote, runbook, materials sha256, and delivered project link (requires paired SIWA agent)."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_orders_create, RegentsWeb.Techtree.AgentTools.Account, :orders_create do
      title("Request a Techtree Uplift Factory order")

      description "Submit a new Techtree Uplift Factory order in one of the four lanes (skills, evals, environments, models) with optional runbook and material archive (requires paired SIWA agent)."

      annotations(
        read_only_hint: false,
        idempotent_hint: false,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :techtree_orders_cancel, RegentsWeb.Techtree.AgentTools.Account, :orders_cancel do
      title("Cancel a Techtree Uplift Factory order")

      description "Cancel an unpaid Techtree Uplift Factory order in state requested, checking, or quoted (requires paired SIWA agent)."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: true,
        open_world_hint: false
      )
    end
  end
end
