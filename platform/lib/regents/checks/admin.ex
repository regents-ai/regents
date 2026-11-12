defmodule Regents.Checks.Admin do
  @moduledoc """
  The actor is one of the site's admins: the team actor the admin pages act as
  (`Regents.Actors.Admin`), whose account the Credits `:admins` setting still
  names.
  """
  use Ash.Policy.SimpleCheck

  alias Regents.Actors.Admin

  @impl true
  def describe(_opts), do: "actor is one of the site's admins"

  @impl true
  def match?(%Admin{} = admin, _context, _opts), do: Regents.Credits.admin?(admin)
  def match?(_actor, _context, _opts), do: false
end
