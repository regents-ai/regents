defmodule RegentPayments.Preparations.ThisSite do
  @moduledoc """
  Keeps every read to the payments of the site asking. All Regent sites share
  one database and this one schema; each reads only the rows it wrote, found
  directly on an intent or `through` the intent a receipt belongs to.
  """

  use Ash.Resource.Preparation

  import Ash.Expr

  @impl true
  def prepare(query, opts, _context) do
    site = RegentPayments.site()

    case opts[:through] do
      nil -> Ash.Query.filter(query, site == ^site)
      relationship -> Ash.Query.filter(query, ^ref([relationship], :site) == ^site)
    end
  end
end
