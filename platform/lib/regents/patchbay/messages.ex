defmodule Regents.Patchbay.Messages do
  @moduledoc """
  Messages left for Patchbay's team: a signed-in person or their paired agent
  leaves one under a topic the site names, such as `agents`, and only
  Patchbay's moderators read them. Nobody else ever sees one, the sender
  included.
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Patchbay.Messages.Message
  end
end
