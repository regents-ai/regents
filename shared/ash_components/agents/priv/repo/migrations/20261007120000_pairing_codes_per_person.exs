defmodule RegentAgents.Migrations.PairingCodesPerPerson do
  @moduledoc """
  A person may hold several live pairing codes: a new code leaves the earlier
  ones working until they expire (Sean, 2026-10-07). Codes are still found by
  their hash, and a person's codes by their Privy user ID.
  """

  use Ecto.Migration

  def change do
    drop(
      unique_index(:pairing_codes, [:privy_user_id],
        prefix: "regent_agents",
        name: :pairing_codes_unique_person_index
      )
    )

    create index(:pairing_codes, [:privy_user_id],
             prefix: "regent_agents",
             name: :pairing_codes_person_index
           )
  end
end
