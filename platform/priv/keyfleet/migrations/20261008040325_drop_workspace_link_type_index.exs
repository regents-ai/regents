defmodule Regents.Repo.Migrations.KeyfleetDropWorkspaceLinkTypeIndex do
  @moduledoc """
  Drops the index of a fleet's workspace links by type: the fleet page's
  "Trying now" no longer lists them, now that only Key holders read links.
  """

  use Ecto.Migration

  def up do
    drop_if_exists(index(:graph_relations, [:fleet_id, :type, :created_seq]))
  end

  def down do
    create index(:graph_relations, [:fleet_id, :type, :created_seq])
  end
end
