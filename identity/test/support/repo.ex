defmodule RegentIdentity.TestRepo do
  use AshPostgres.Repo, otp_app: :regent_identity, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: []
end

defmodule RegentIdentity.SecondRepo do
  use AshPostgres.Repo, otp_app: :regent_identity, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: []
end
