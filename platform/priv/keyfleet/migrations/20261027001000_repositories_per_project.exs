defmodule Regents.Repo.Migrations.KeyfleetRepositoriesPerProject do
  @moduledoc """
  Each project has its own repository. A repository made in the code store is
  now kept by its name: each one made so far is its fleet's first, named
  after the fleet, which is `general`'s. Every push sent so far went to
  `general`.
  """

  use Ecto.Migration

  def up do
    rename(table(:code_repositories), :fleet_id, to: :repository)

    alter table(:code_pushes) do
      add(:project, :text, null: false, default: "general")
    end

    alter table(:code_pushes) do
      modify(:project, :text, default: nil)
    end

    drop(index(:code_pushes, [:fleet_id, :pushed_at]))
    create index(:code_pushes, [:fleet_id, :project, :pushed_at])
  end

  def down do
    drop(index(:code_pushes, [:fleet_id, :project, :pushed_at]))
    create index(:code_pushes, [:fleet_id, :pushed_at])

    alter table(:code_pushes) do
      remove(:project)
    end

    rename(table(:code_repositories), :repository, to: :fleet_id)
  end
end
