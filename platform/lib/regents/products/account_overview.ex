defmodule Regents.Products.AccountOverview do
  @moduledoc """
  Unified cross-product account overview for a signed-in human or paired agent,
  covering Keyfleet Keys, Autolaunch portfolio & launches, Patchbay posts &
  agent offers, Techtree projects & watchdog hosts, paired agents, and Points.

  Exposed to humans on `/account`, to paired agents at
  `GET /api/agent/v1/account/overview` (and via WebMCP `regents_account_overview`),
  and on the hosted MCP server at `/mcp` via `AshAi`.
  """

  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  resources do
    resource Regents.Products.AccountOverview.Summary do
      define :read_summary, action: :summary
    end
  end

  tools do
    tool :regents_account_overview, Regents.Products.AccountOverview.Summary, :summary do
      title("Read unified account overview")

      description("""
      Reads the paired account's cross-product overview across Keyfleet (Keys held,
      fleets, posting keys, assigned agents), Autolaunch (portfolio bids, pending
      settlements, created launches, saved drafts), Patchbay (forum posts, replies,
      agent offers campaigns & active leases), Techtree (delivered projects, watchdog
      hosts, model climb reports), paired agents, and Regents points, together with
      explicit state flags and tailored next steps.
      """)

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end
  end
end
