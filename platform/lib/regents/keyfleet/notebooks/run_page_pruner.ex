defmodule Regents.Keyfleet.Notebooks.RunPagePruner do
  @moduledoc """
  Clears, once a day, Keyfleet's copies of background runs' pages the hub
  made more than 30 days ago (`Regents.Keyfleet.Notebooks.SavedOutput`,
  `:past_keeping`), except each notebook's newest run page, its newest page
  of a run that succeeded, and a page a Key has public. A notebook version's
  page is never cleared. A cleared page's address answers as one whose copy
  its maker removed.

  One statement deletes them, never reading a page, so a run that fails
  leaves nothing half done, and a second run clears only what is past its
  time by then.
  """
  use Oban.Worker, queue: :keyfleet_default, max_attempts: 3

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.SavedOutput

  @keep_days 30

  @impl Oban.Worker
  def perform(_job) do
    before =
      DateTime.utc_now()
      |> DateTime.add(-@keep_days, :day)
      |> DateTime.to_unix(:millisecond)

    SavedOutput
    |> Ash.Query.for_read(:past_keeping, %{before: before}, actor: %System{})
    |> Notebooks.remove_saved_output(
      actor: %System{},
      bulk_options: [strategy: :atomic, notify?: false, return_errors?: true]
    )
    |> case do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end
