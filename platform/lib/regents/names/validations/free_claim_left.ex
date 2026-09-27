defmodule Regents.Names.Validations.FreeClaimLeft do
  @moduledoc """
  A free claim is spent only while one is left, checked in the update's own SQL
  against the row as it is now, so two claims racing for a wallet's last one
  cannot both succeed.
  """
  use Ash.Resource.Validation

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:free_mints_used, :snapshot_total], expr(free_mints_used >= snapshot_total),
     expr(
       error(Ash.Error.Changes.InvalidAttribute, %{
         field: :free_mints_used,
         value: free_mints_used,
         message: "no free claims are left"
       })
     )}
  end
end
