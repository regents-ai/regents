defmodule Regents.Patchbay.Forum.Changes.AnnounceThread do
  @moduledoc """
  Queues the thread's address for the search engines that read IndexNow
  (`Regents.Patchbay.IndexNow`) in the same transaction as the event that changed its
  page: a new thread, a new reply or a marked answer. Nothing is queued while
  no IndexNow key is set.
  """

  use Ash.Resource.Change

  alias Regents.Patchbay.Forum.PostAddress

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, event ->
      if Regents.Patchbay.IndexNow.key() do
        # The address is the thread's own, made from its headline's words.
        %{thread: thread} =
          Ash.load!(event, [thread: PostAddress.report_query()], authorize?: false)

        [PostAddress.url(thread)]
        |> Regents.Patchbay.IndexNow.submit()
        |> Oban.insert!()
      end

      {:ok, event}
    end)
  end
end
