defmodule RegentPayments.TestRepo do
  @moduledoc """
  The repository a site hands the library, as a site's own is set up: with
  Ash's database functions, which the payment policies need for their atomic
  updates.
  """
  use AshPostgres.Repo, otp_app: :regent_payments, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: ["ash-functions"]
end

defmodule RegentPayments.TestRepo.AshFunctions do
  @moduledoc "Installs Ash's database functions in the test database, as a site's migrations do."
  use Ecto.Migration

  def up do
    AshPostgres.MigrationGenerator.AshFunctions.install(nil)
    |> Code.eval_string([], __ENV__)
  end
end
