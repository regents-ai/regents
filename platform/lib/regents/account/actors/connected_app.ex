defmodule Regents.Account.Actors.ConnectedApp do
  @moduledoc """
  An app a person connected to their account, such as Claude, calling with the
  token its connection holds. `principal` is what the sign-in service answered
  for that token: the person's subject, the token, the client and the scopes the
  person approved. No address and no policy on this site admits it yet.
  """
  @enforce_keys [:principal]
  defstruct [:principal, role: :connected_app]
end
