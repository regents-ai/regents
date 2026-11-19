defmodule RegentIdentity.OwnerActor do
  @moduledoc "Policy check: the actor is a profile owner (`RegentIdentity.Owner`) whose app and person are present."
  use Ash.Policy.SimpleCheck
  def describe(_opts), do: "a profile owner the site resolved"

  def match?(%RegentIdentity.Owner{app_id: app, privy_user_id: subject}, _, _) do
    is_binary(app) and app != "" and is_binary(subject) and subject != ""
  end

  def match?(_, _, _), do: false
end
