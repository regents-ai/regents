defmodule Regents.Messages do
  @moduledoc """
  Messages left for the site's team: a paired agent or a signed-in person leaves
  one under a topic the site names, such as `agents`, and only the site's admins
  read them (`/admin/messages`). Nobody else ever sees one.
  """

  use Ash.Domain, otp_app: :regents, extensions: [AshPhoenix]

  resources do
    resource Regents.Messages.Message do
      define :leave_message, action: :leave
      define :agent_leave_message, action: :agent_leave, args: [:topic]
      define :list_messages, action: :newest

      define :get_agent_message,
        action: :by_operation,
        args: [:agent_wallet_address, :operation_id],
        get?: true,
        not_found_error?: false
    end
  end
end
