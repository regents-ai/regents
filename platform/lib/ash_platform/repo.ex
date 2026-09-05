defmodule AshPlatform.Repo do
  use AshPostgres.Repo, otp_app: :ash_platform

  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: ["ash-functions"]
end
