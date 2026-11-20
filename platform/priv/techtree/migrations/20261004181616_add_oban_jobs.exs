defmodule Regents.Repo.Migrations.TechtreeAddObanJobs do
  @moduledoc """
  Background jobs, in this site's own schema: the repo's, which a release also
  migrates with. `prefix()` holds it only when the runner was given one.
  """

  use Ecto.Migration

  def up, do: Oban.Migrations.up(prefix: prefix())

  def down, do: Oban.Migrations.down(prefix: prefix(), version: 1)
end
