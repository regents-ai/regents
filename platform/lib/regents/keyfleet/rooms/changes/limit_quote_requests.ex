defmodule Regents.Keyfleet.Rooms.Changes.LimitQuoteRequests do
  @moduledoc """
  Holds what a person sends their agent from fleets' pages to 300 requests an
  hour across every fleet, counted from the requests stored in the last hour.

  People send from the page, which the API's per-address limit doesn't reach.
  A refused request stores nothing, so it never counts. The count is the
  database's, so every machine sees the same one and a deploy keeps it. It
  runs after `Regents.Keyfleet.Rooms.Changes.NextQuotePlace` has taken the person's
  lock in the fleet; two requests at the same moment in two fleets may both
  get through, which a guard against flooding allows.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Regents.Keyfleet.Rooms.Errors.QuoteLimitError
  alias Regents.Keyfleet.Rooms.QuoteRequest

  @limit 300
  @hour 3_600

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.before_action(changeset, &limit/1)

  defp limit(changeset) do
    account_id = Ash.Changeset.get_attribute(changeset, :human_account_id)

    # The 300th newest request of the hour: while there is one, the person is
    # at their limit until that request is an hour old. Read as the server's
    # own count of the person's requests, which the action's policy has
    # already allowed them to add to.
    case QuoteRequest
         |> Ash.Query.filter(human_account_id == ^account_id and inserted_at > ago(1, :hour))
         |> Ash.Query.sort(inserted_at: :desc, id: :asc)
         |> Ash.Query.offset(@limit - 1)
         |> Ash.Query.limit(1)
         |> Ash.read!(authorize?: false) do
      [] -> changeset
      [oldest] -> Ash.Changeset.add_error(changeset, refusal(oldest))
    end
  end

  defp refusal(%QuoteRequest{inserted_at: oldest}) do
    seconds = DateTime.diff(DateTime.add(oldest, @hour), DateTime.utc_now(), :second)
    QuoteLimitError.exception(limit: @limit, retry_after: max(seconds, 1))
  end
end
