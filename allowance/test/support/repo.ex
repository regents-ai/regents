defmodule RegentAllowance.TestRepo do
  @moduledoc "The repository a site hands the library."
  use AshPostgres.Repo, otp_app: :regent_allowance, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: []
end
