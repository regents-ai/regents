defmodule Regents.Blog.Checks.Admin do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor's verified account is a Credits admin"

  @impl true
  def match?(%Regents.Actors.Human{human_account_id: id} = actor, _context, _opts) do
    case Regents.Accounts.get_human_account(id, actor: actor) do
      {:ok, account} -> Regents.Blog.admin?(account)
      _ -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
