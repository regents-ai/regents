defmodule Regents.Updates do
  @moduledoc """
  The email addresses visitors leave to hear when something is ready, such as
  Cloak's download (`/cloak`). The site only keeps them; nothing here sends mail,
  and no page or tool reads them back.
  """

  use Ash.Domain, otp_app: :regents, extensions: [AshPhoenix]

  resources do
    resource Regents.Updates.Subscriber do
      define :subscribe_to_updates, action: :subscribe
    end
  end
end
