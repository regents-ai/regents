defmodule Regents.Updates do
  @moduledoc """
  The email addresses visitors leave to hear news, such as Cloak's releases
  (`/cloak/download`). The site only keeps them; nothing here sends mail,
  and no page or tool reads them back.
  """

  use Ash.Domain, otp_app: :regents, extensions: [AshPhoenix]

  resources do
    resource Regents.Updates.Subscriber do
      define :subscribe_to_updates, action: :subscribe
    end
  end
end
