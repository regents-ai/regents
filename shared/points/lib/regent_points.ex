defmodule RegentPoints do
  @moduledoc "Server-owned points intake and the account's private, append-only ledger."
  use Ash.Domain, otp_app: :regent_points

  @doc false
  def repo(_resource, _operation), do: Application.fetch_env!(:regent_points, :repo)
  @doc false
  def accounts, do: Application.fetch_env!(:regent_points, :accounts)
  @doc false
  def chain_client, do: Application.fetch_env!(:regent_points, :chain_client)

  resources do
    resource RegentPoints.PeriodSnapshot
    resource RegentPoints.WalletSnapshot
    resource RegentPoints.WalletCoverage

    resource RegentPoints.HumanAccount do
      define :read_human_references, action: :read
    end

    resource RegentPoints.Rejection do
      define :reject_source, action: :record
      define :read_rejections, action: :read
    end

    resource RegentPoints.Account do
      define :open_account, action: :open
      define :read_accounts, action: :read
      define :add_to_balance, action: :add_to_balance, args: [:points_micro]
    end

    resource RegentPoints.Event do
      define :create_event, action: :record
      define :read_events, action: :read
      define :finish_event, action: :finish
    end

    resource RegentPoints.Entry do
      define :append_entry, action: :append
      define :read_entries, action: :read
      define :history, action: :history
    end

    resource RegentPoints.CapUsage do
      define :reserve_cap, action: :reserve
      define :read_caps, action: :read
      define :consume_cap, action: :consume, args: [:points]
    end

    resource RegentPoints.PeriodBonus do
      define :record_period_bonus, action: :record
      define :read_period_bonuses, action: :read
      define :follow_period_bonus, action: :follow
    end

    resource RegentPoints.Service do
      define :summary, action: :summary
      define :leaderboard, action: :leaderboard
      define :record_event, action: :record_event, args: [:event]
      define :process_event, action: :process_event, args: [:event_id]

      define :reverse,
        action: :reverse,
        args: [:entry_id, :correction_key, :points_micro, :reason]
    end
  end
end
