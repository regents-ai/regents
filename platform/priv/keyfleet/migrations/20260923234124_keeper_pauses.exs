defmodule Regents.Repo.Migrations.KeyfleetKeeperPauses do
  @moduledoc """
  Lets a keeper run record which pause ended, and the fleet a VRF balance
  pause is for. Generated with `mix ash.codegen`.
  """

  use Ecto.Migration

  def up do
    alter table(:keeper_runs) do
      add(
        :fleet_id,
        references(:fleets,
          column: :id,
          name: "keeper_runs_fleet_id_fkey",
          type: :text,
          prefix: "keyfleet_app"
        )
      )
    end

    drop_if_exists(constraint(:keeper_runs, :keeper_runs_outcome))

    create constraint(:keeper_runs, :keeper_runs_outcome,
             check: """
               outcome IN ('sent', 'paused_gas', 'unpaused_gas', 'paused_vrf_balance', 'unpaused_vrf_balance', 'paused_spend_ceiling', 'unpaused_spend_ceiling', 'stopped', 'resumed', 'error')
             """
           )

    create constraint(:keeper_runs, :keeper_runs_vrf_balance_has_fleet,
             check: """
               (outcome IN ('paused_vrf_balance', 'unpaused_vrf_balance')) = (fleet_id IS NOT NULL)
             """
           )
  end

  def down do
    drop_if_exists(constraint(:keeper_runs, :keeper_runs_vrf_balance_has_fleet))

    drop_if_exists(constraint(:keeper_runs, :keeper_runs_outcome))

    create constraint(:keeper_runs, :keeper_runs_outcome,
             check: """
               outcome IN ('sent', 'paused_gas', 'paused_vrf_balance', 'paused_spend_ceiling', 'stopped', 'resumed', 'error')
             """
           )

    drop(constraint(:keeper_runs, "keeper_runs_fleet_id_fkey"))

    alter table(:keeper_runs) do
      remove(:fleet_id)
    end
  end
end
