defmodule Regents.Repo.Migrations.KeyfleetFleetsOnTheFactory do
  @moduledoc """
  Fleets live on the factory contracts: each records its number in the shared
  Key collection, the collection itself and its manager, which takes the place
  of the one contract a fleet had, and its card deck's hash and size. A Key's
  presence records include its automatic start two days after its sale. No
  fleet holds a deployment yet.
  """

  use Ecto.Migration

  def up do
    alter table(:fleets) do
      add(:chain_fleet_id, :bigint)
      add(:keys_address, :text)
      add(:manager_address, :text)
      add(:deck_hash, :text)
      add(:deck_size, :bigint)
    end

    drop_if_exists(constraint(:fleets, :fleets_deployment_whole))

    drop_if_exists(constraint(:fleets, :fleets_contract_address_shape))

    alter table(:fleets) do
      remove(:contract_address)
    end

    create constraint(:fleets, :fleets_deployment_whole,
             check: """
               num_nulls(chain_id, chain_fleet_id, keys_address, manager_address, rewards_address, votes_address, treasury_address, shards_address, usdc_address, regent_address, regent_staking_address, autolaunch_factory_address, deployed_block, trait_table_hash, deck_hash, deck_size) IN (0, 16)
             """
           )

    create constraint(:fleets, :fleets_keys_address_shape,
             check: """
               keys_address ~ '^0x[0-9a-f]{40}$'
             """
           )

    create constraint(:fleets, :fleets_manager_address_shape,
             check: """
               manager_address ~ '^0x[0-9a-f]{40}$'
             """
           )

    create constraint(:fleets, :fleets_chain_fleet_id_positive,
             check: """
               chain_fleet_id > 0
             """
           )

    create constraint(:fleets, :fleets_deck_hash_shape,
             check: """
               deck_hash ~ '^0x[0-9a-f]{64}$'
             """
           )

    create constraint(:fleets, :fleets_deck_size_positive,
             check: """
               deck_size > 0
             """
           )

    drop_if_exists(constraint(:key_presences, :key_presences_shape))

    create constraint(:key_presences, :key_presences_shape,
             check: """
               (kind = 'present' AND at IS NOT NULL AND ownership_epoch >= 1)
             OR (kind = 'scheduled' AND at IS NOT NULL AND ownership_epoch IS NULL)
             OR (kind = 'cleared' AND at IS NULL AND ownership_epoch IS NULL)

             """
           )
  end

  def down do
    drop_if_exists(constraint(:key_presences, :key_presences_shape))

    create constraint(:key_presences, :key_presences_shape,
             check: """
               (kind = 'present' AND at IS NOT NULL AND ownership_epoch >= 1)
             OR (kind = 'cleared' AND at IS NULL AND ownership_epoch IS NULL)

             """
           )

    drop_if_exists(constraint(:fleets, :fleets_deck_size_positive))

    drop_if_exists(constraint(:fleets, :fleets_deck_hash_shape))

    drop_if_exists(constraint(:fleets, :fleets_chain_fleet_id_positive))

    drop_if_exists(constraint(:fleets, :fleets_manager_address_shape))

    drop_if_exists(constraint(:fleets, :fleets_keys_address_shape))

    drop_if_exists(constraint(:fleets, :fleets_deployment_whole))

    alter table(:fleets) do
      add(:contract_address, :text)
    end

    create constraint(:fleets, :fleets_contract_address_shape,
             check: """
               contract_address ~ '^0x[0-9a-f]{40}$'
             """
           )

    create constraint(:fleets, :fleets_deployment_whole,
             check: """
               num_nulls(chain_id, contract_address, rewards_address, votes_address, treasury_address, shards_address, usdc_address, regent_address, regent_staking_address, autolaunch_factory_address, deployed_block, trait_table_hash) IN (0, 12)
             """
           )

    alter table(:fleets) do
      remove(:deck_size)
      remove(:deck_hash)
      remove(:manager_address)
      remove(:keys_address)
      remove(:chain_fleet_id)
    end
  end
end
