defmodule Regents.Repo.Migrations.KeyfleetKeyProfile do
  @moduledoc """
  Indexes a key's profile reads: the keys a wallet holds across fleets, the
  votes a key was used in, and the votes a wallet cast in a fleet. Generated
  with `mix ash.codegen`.
  """

  use Ecto.Migration

  def up do
    create index(:key_attachments, [:owner_wallet])

    create index(:proposal_votes, [:token_ids], using: "GIN")

    create index(:proposal_votes, [:fleet_id, :voter])
  end

  def down do
    drop_if_exists(index(:proposal_votes, [:fleet_id, :voter]))

    drop_if_exists(index(:proposal_votes, [:token_ids]))

    drop_if_exists(index(:key_attachments, [:owner_wallet]))
  end
end
