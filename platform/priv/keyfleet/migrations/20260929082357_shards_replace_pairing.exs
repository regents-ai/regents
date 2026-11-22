defmodule Regents.Repo.Migrations.KeyfleetShardsReplacePairing do
  @moduledoc """
  Shards replace one-agent pairing: the pairings table goes, with the two
  functions its triggers ran, and each person's or agent's mutes of keys get
  a table of their own.

  Generated with `mix ash.codegen`; the two function drops were added by hand.
  """

  use Ecto.Migration

  def up do
    drop(table(:key_pairings))
    execute("DROP FUNCTION keyfleet_app.protect_key_pairing();")
    execute("DROP FUNCTION keyfleet_app.refuse_key_pairing_truncate();")

    create table(:mutes, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:muter, :text, null: false)
      add(:token_id, :bigint, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :fleet_id,
        references(:fleets,
          column: :id,
          name: "mutes_fleet_id_fkey",
          type: :text,
          prefix: "keyfleet_app"
        ), null: false)
    end

    create unique_index(:mutes, [:muter, :fleet_id, :token_id], name: "mutes_one_per_key_index")

    create constraint(:mutes, :mutes_positive_token,
             check: """
               token_id > 0
             """
           )

    create constraint(:mutes, :mutes_muter_shape,
             check: """
               muter ~ '^(human:[1-9][0-9]*|agent:0x[0-9a-f]{40})$'
             """
           )
  end

  def down do
    drop_if_exists(constraint(:mutes, :mutes_muter_shape))

    drop_if_exists(constraint(:mutes, :mutes_positive_token))

    drop(constraint(:mutes, "mutes_fleet_id_fkey"))

    drop_if_exists(
      unique_index(:mutes, [:muter, :fleet_id, :token_id], name: "mutes_one_per_key_index")
    )

    drop(table(:mutes))

    # The pairings table and its functions are not made again.
  end
end
