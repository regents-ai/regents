defmodule Regents.Patchbay.Assist do
  @moduledoc """
  Assists: somebody stuck on a site's tools tells Patchbay what they are trying
  to do, and Patchbay works out the right call for them. Each run, its
  decisions and its model calls are kept.
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Patchbay.Assist.Run
    resource Regents.Patchbay.Assist.Decision
    resource Regents.Patchbay.Assist.ModelCall
  end
end
