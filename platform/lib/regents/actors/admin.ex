defmodule Regents.Actors.Admin do
  @moduledoc """
  A signed-in account acting as one of the site's admins on a team page
  (`RegentsWeb.ErrorsAdmin`). `Regents.Checks.Admin` checks it again in each
  policy.
  """
  @enforce_keys [:privy_user_id]
  defstruct [:privy_user_id, role: :admin]
end
