defmodule RegentsWeb.Keyfleet.AgentTools.Chain do
  @moduledoc """
  Non-custodial transaction builders for Keyfleet's on-chain contracts:
  marking keys present, proposing, voting, cancelling, carrying out proposals,
  running the daily split, sending the staking share, converting waiting USDC
  to REGENT, returning treasury advances, running token-launch upkeep,
  claiming rewards, buying a Key, claiming a Regents Club Key, requesting or
  expiring a reveal, and managing shards.

  Each action builds unsigned transaction calldata for the calling paired
  agent's own wallet (`RegentsWeb.Keyfleet.AgentTools.Chain.Answer`), with the
  exact validation and refusal shape of Keyfleet's signed HTTP endpoints
  (`RegentsWeb.Keyfleet.AgentChainController`). Nothing here signs or sends
  any transaction.
  """
  use Ash.Resource,
    domain: RegentsWeb.Keyfleet.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentsWeb.Keyfleet.AgentTools.Run

  @fleet [max_length: 63, trim?: false]
  @key [match: ~r/\A[1-9][0-9]{0,17}\z/, max_length: 18, trim?: false]
  @as_sent [trim?: false, allow_empty?: true]

  actions do
    action :presence, :map do
      description "Builds the unsigned transaction marking your keys present in a fleet."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "chain_presence"}
    end

    action :propose, :map do
      description "Saves proposal text and builds the unsigned transaction to create a fleet proposal."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :kind, :string, allow_nil?: false, constraints: @as_sent
      argument :key, :string, allow_nil?: false, constraints: @as_sent
      argument :text, :string, allow_nil?: false, constraints: @as_sent
      argument :asset, :string, constraints: @as_sent
      argument :share, :string, constraints: @as_sent
      argument :recipient, :string, constraints: @as_sent
      argument :rate, :string, constraints: @as_sent
      argument :target, :string, constraints: @as_sent
      argument :restricted, :string, constraints: @as_sent
      argument :name, :string, constraints: @as_sent
      argument :symbol, :string, constraints: @as_sent
      argument :description, :string, constraints: @as_sent
      argument :website, :string, constraints: @as_sent
      argument :image, :string, constraints: @as_sent
      run {Run, tool: "chain_propose"}
    end

    action :vote, :map do
      description "Builds the unsigned transaction to vote yes, no, or abstain on a fleet proposal."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :number, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: 9_223_372_036_854_775_807]

      argument :choice, :string, allow_nil?: false, constraints: [max_length: 16, trim?: false]
      run {Run, tool: "chain_vote"}
    end

    action :cancel, :map do
      description "Builds the unsigned transaction to cancel a fleet proposal you made."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :number, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: 9_223_372_036_854_775_807]

      run {Run, tool: "chain_cancel"}
    end

    action :carry_out, :map do
      description "Builds the unsigned transaction to carry out a passed fleet proposal."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet

      argument :number, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: 9_223_372_036_854_775_807]

      run {Run, tool: "chain_carry_out"}
    end

    action :split, :map do
      description "Builds the unsigned transaction to run the fleet's daily treasury split."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "chain_split"}
    end

    action :send_share, :map do
      description "Builds the unsigned transaction to send the fleet's owed REGENT staking share."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "chain_send_share"}
    end

    action :convert, :map do
      description "Builds the unsigned transaction to convert waiting treasury USDC into REGENT."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :inputs, :map, allow_nil?: false
      run {Run, tool: "chain_convert"}
    end

    action :return_advance, :map do
      description "Builds the unsigned transactions to return part or all of a treasury advance."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :advance_id, :string, allow_nil?: false, constraints: @key
      argument :amount, :string, allow_nil?: false, constraints: [max_length: 100, trim?: false]
      run {Run, tool: "chain_return_advance"}
    end

    action :launch_upkeep, :map do
      description "Builds the unsigned transaction for a fleet token-launch upkeep step (settle, bind, release, or collect)."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :step, :string, allow_nil?: false, constraints: [max_length: 16, trim?: false]
      run {Run, tool: "chain_launch_upkeep"}
    end

    action :claim, :map do
      description "Builds the unsigned transaction to claim one Key's waiting rewards."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: @key
      run {Run, tool: "chain_claim"}
    end

    action :claim_all, :map do
      description "Builds the unsigned transaction to claim rewards for every Key your wallet holds in a fleet."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "chain_claim_all"}
    end

    action :buy, :map do
      description "Builds the unsigned transactions to buy the next available Key in a fleet."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      run {Run, tool: "chain_buy"}
    end

    action :issue_shard, :map do
      description "Builds the unsigned transaction to issue or renew shards of your Keys for an agent wallet."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :keys, :string, allow_nil?: false, constraints: [max_length: 1000, trim?: false]
      argument :wallet, :string, allow_nil?: false, constraints: [max_length: 100, trim?: false]
      argument :days, :string, allow_nil?: false, constraints: [max_length: 10, trim?: false]
      run {Run, tool: "chain_issue_shard"}
    end

    action :agent_voting, :map do
      description "Builds the unsigned transaction to turn shard voting and proposing on or off for your Keys."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :keys, :string, allow_nil?: false, constraints: [max_length: 1000, trim?: false]
      argument :voting, :string, allow_nil?: false, constraints: [max_length: 8, trim?: false]
      run {Run, tool: "chain_agent_voting"}
    end

    action :end_shard, :map do
      description "Builds the unsigned transaction to end active shards on one Key."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: @key
      run {Run, tool: "chain_end_shard"}
    end

    action :club_claim, :map do
      description "Builds the unsigned transaction to claim a Regents Club Key with its matching Pass."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: @key
      run {Run, tool: "chain_club_claim"}
    end

    action :reveal, :map do
      description "Builds the unsigned transaction to request a Key's trait draw again after a refused request."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: @key
      run {Run, tool: "chain_reveal"}
    end

    action :expire_reveal, :map do
      description "Builds the unsigned transaction to expire an unfulfilled Key trait draw after 24 hours."
      argument :fleet_id, :string, allow_nil?: false, constraints: @fleet
      argument :token_id, :string, allow_nil?: false, constraints: @key
      run {Run, tool: "chain_expire_reveal"}
    end
  end

  policies do
    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end
end
