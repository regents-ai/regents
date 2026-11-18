defmodule Regents.Updates.Subscriber.LimitTries do
  @moduledoc """
  Holds each network to `:updates_rate_limit` addresses a window, counted in
  `Regents.RateLimiter`. The caller passes the client address tag as
  `context: %{client_key: tag}` (`RegentsWeb.ClientAddress.tag/1`). An address
  counts when it would be kept, never while it is typed.
  """

  use Ash.Resource.Change

  alias Regents.RateLimiter

  @too_many "Too many tries. Wait a minute and try again."

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      %{client_key: key} = changeset.context
      budget = Application.fetch_env!(:regents, :updates_rate_limit)

      case RateLimiter.admit(
             {:updates, key},
             Keyword.fetch!(budget, :limit),
             Keyword.fetch!(budget, :window_seconds)
           ) do
        {:ok, _budget} ->
          changeset

        {:error, :rate_limited, _budget} ->
          Ash.Changeset.add_error(changeset, field: :address, message: @too_many)
      end
    end)
  end
end
