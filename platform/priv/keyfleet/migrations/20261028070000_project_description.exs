defmodule Regents.Repo.Migrations.KeyfleetProjectDescription do
  @moduledoc """
  A project's one-line description, which its page shows under the title and
  shares as its description. Every project starts with none.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:projects) do
      add(:description, :text)
    end
  end
end
