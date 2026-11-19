defmodule RegentPoints.Enqueue do
  @moduledoc """
  Queues Points work in the host's source transaction, on the site's Oban with the
  same Repo. The job commits or rolls back with the source action, so a committed
  action always has its job; an insert failure raises and the source rolls back.
  """
  def call(job), do: {:ok, %{status: :queued, id: Oban.insert!(job).id}}
end
