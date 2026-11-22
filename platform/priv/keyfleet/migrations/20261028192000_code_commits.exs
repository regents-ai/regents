defmodule Regents.Repo.Migrations.KeyfleetCodeCommits do
  @moduledoc """
  The push that first sent each commit to a project's repository
  (`Keyfleet.Code.Commit`), gone with its push. It starts empty; the pushes
  already recorded are filled in once by `Keyfleet.Code.Sent.backfill/0`.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create table(:code_commits, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:fleet_id, :text, null: false)
      add(:project, :text, null: false)
      add(:hash, :text, null: false)

      add(
        :push_id,
        references(:code_pushes,
          column: :id,
          name: "code_commits_push_id_fkey",
          type: :uuid,
          prefix: "keyfleet_app",
          on_delete: :delete_all
        ),
        null: false
      )
    end

    create unique_index(:code_commits, [:fleet_id, :project, :hash],
             name: "code_commits_commit_index"
           )

    create index(:code_commits, [:push_id])
  end
end
