defmodule Regents.Repo.Migrations.DropRegentAllowance do
  @moduledoc """
  The shared OpenAI allowance was removed in Regents v121, so its empty table
  and schema go. Sean chose this on 1 October 2026 ("1 a") and unlocked the
  table first. A database the allowance never reached has nothing to remove.
  The schema lies outside `regents_app`, so the statements name it in full.
  """

  use Ecto.Migration

  def up do
    execute("DROP TABLE IF EXISTS regent_allowance.openai_calls")
    execute("DROP TABLE IF EXISTS regent_allowance.schema_migrations")
    execute("DROP SCHEMA IF EXISTS regent_allowance")
  end

  def down, do: raise(Ecto.MigrationError, "the removed OpenAI allowance cannot be restored")
end
