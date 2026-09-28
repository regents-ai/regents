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

defmodule RegentPayments.TestRepo.PaymentEffects do
  @moduledoc """
  The test site's own record of what each payment bought: one row per intent,
  held unique by its key, counting the carry outs that were saved.
  """
  use Ecto.Migration

  def change do
    create table(:payment_effects, primary_key: false) do
      add(:payment_intent_id, :uuid, primary_key: true)
      add(:carried_out, :integer, null: false, default: 1)
    end
  end
end
