defmodule RegentIdentity.VerifiedActor do
  use Ash.Policy.SimpleCheck
  def describe(_opts), do: "a currently verified Privy token pair"

  def match?(%RegentPrivy.Session{app_id: app, privy_user_id: subject, expires_at: expiry}, _, _) do
    is_binary(app) and app != "" and is_binary(subject) and subject != "" and
      is_integer(expiry) and expiry > System.system_time(:second)
  end

  def match?(_, _, _), do: false
end
