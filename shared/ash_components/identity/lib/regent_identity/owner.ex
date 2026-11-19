defmodule RegentIdentity.Owner do
  @moduledoc """
  Whose profile is read or changed: the person `privy_user_id` of the Privy app
  `app_id`. The site decides who that is from its own sign-in, such as its
  session or an agent the person paired, and hands it to the profile API with
  `RegentIdentity.HTTP.put_owner/2`. It is the actor of `get_my_profile/1` and
  `edit_profile/3`.
  """

  @enforce_keys [:app_id, :privy_user_id]
  defstruct [:app_id, :privy_user_id]

  @type t :: %__MODULE__{app_id: String.t(), privy_user_id: String.t()}

  @doc "The owner a verified Privy sign-in names."
  @spec of(RegentPrivy.Session.t()) :: t()
  def of(%RegentPrivy.Session{app_id: app_id, privy_user_id: privy_user_id}),
    do: %__MODULE__{app_id: app_id, privy_user_id: privy_user_id}
end
