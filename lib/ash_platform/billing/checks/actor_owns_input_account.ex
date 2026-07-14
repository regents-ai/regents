defmodule AshPlatform.Billing.Checks.ActorOwnsInputAccount do
  use Ash.Policy.SimpleCheck
  alias AshPlatform.Actors.Human

  @impl true
  def describe(_opts), do: "actor owns the requested account"

  @impl true
  def match?(%Human{human_account_id: id}, %{subject: input}, _opts) do
    Ash.ActionInput.get_argument(input, :human_account_id) == id
  end

  def match?(_, _, _), do: false
end
