defmodule Regents.Repo.Migrations.KeyfleetKeeperStopState do
  @moduledoc """
  Lets a keeper run record why the keeper stopped, and a later run that
  resumes it: a stop, and only a stop, names one of the known reasons.
  """

  use Ecto.Migration

  def up do
    alter table(:keeper_runs) do
      add(:stop_reason, :text)
    end

    drop_if_exists(constraint(:keeper_runs, :keeper_runs_outcome))

    create constraint(:keeper_runs, :keeper_runs_outcome,
             check: """
               outcome IN ('sent', 'paused_gas', 'paused_vrf_balance', 'paused_spend_ceiling', 'stopped', 'resumed', 'error')
             """
           )

    create constraint(:keeper_runs, :keeper_runs_stop_reason,
             check: """
               stop_reason IN ('foreign_nonce', 'replaced_externally', 'tx_hash_mismatch')
             """
           )

    create constraint(:keeper_runs, :keeper_runs_stop_has_reason,
             check: """
               (outcome = 'stopped') = (stop_reason IS NOT NULL)
             """
           )
  end

  def down do
    drop_if_exists(constraint(:keeper_runs, :keeper_runs_stop_has_reason))

    drop_if_exists(constraint(:keeper_runs, :keeper_runs_stop_reason))

    drop_if_exists(constraint(:keeper_runs, :keeper_runs_outcome))

    create constraint(:keeper_runs, :keeper_runs_outcome,
             check: """
               outcome IN ('sent', 'paused_gas', 'paused_vrf_balance', 'paused_spend_ceiling', 'stopped', 'error')
             """
           )

    alter table(:keeper_runs) do
      remove(:stop_reason)
    end
  end
end
