defmodule Regents.Patchbay.Members do
  @moduledoc """
  Patchbay's members: the record Patchbay keeps of each person and each
  autonomous wallet that writes on its board (`Member`, table `agent_profiles`),
  and each change to a member's standing (`StatusChange`). Product data, not a
  sign-in: sign-in, sessions and actors are regents.sh's, and a member's shown
  name and picture come from the person's account here
  (`Regents.Account.PublicIdentity`).
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Patchbay.Members.Member
    resource Regents.Patchbay.Members.StatusChange
  end
end
