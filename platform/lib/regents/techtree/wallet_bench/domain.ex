defmodule Regents.Techtree.WalletBench do
  @moduledoc """
  AgentWalletBench, read only: which coding agent can install and use which
  wallet tool, from the tests techtree.sh's bench runs on clean machines.

  This site reads the bench's rows where they already are, in Techtree's own
  schema (`techtree_app`): the attempts, their turns, the machines they ran on,
  the funding sends of a money attempt, what happened in each attempt, and the
  extra notes on agent and wallet releases. Every resource here has read
  actions only and no migration: running, judging and funding tests stays on
  techtree.sh's app, which writes these rows (`SOURCE.json` names what was not
  brought).
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Techtree.WalletBench.Machine

    resource Regents.Techtree.WalletBench.Attempt do
      define :get_attempt, action: :read, get_by: [:id]
      define :list_attempts, action: :recent
    end

    resource Regents.Techtree.WalletBench.Payment

    resource Regents.Techtree.WalletBench.Turn

    resource Regents.Techtree.WalletBench.AttemptEvent do
      define :list_attempt_events, action: :for_attempt, args: [:attempt_id]
    end

    resource Regents.Techtree.WalletBench.VersionNote do
      define :list_version_notes, action: :listed

      define :list_run_version_notes,
        action: :for_run,
        args: [:harness_id, :harness_version, :wallet_id, :wallet_version]
    end
  end
end
