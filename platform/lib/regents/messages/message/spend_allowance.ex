defmodule Regents.Messages.Message.SpendAllowance do
  @moduledoc """
  Holds each person, with the agents paired with them, to `:message_rate_limit`
  messages a window, and each network to `:message_address_rate_limit`, counted
  in `Regents.RateLimiter`. The caller passes the client address tag as
  `context: %{client_key: tag}` (`RegentsWeb.ClientAddress.tag/1`). A message
  counts when it is saved, never while it is typed.
  """

  use Ash.Resource.Change

  alias Regents.RateLimiter

  @quickly "You're going quickly. Wait a moment and try again."

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      %{human_account_id: person} = changeset.attributes
      %{client_key: key} = changeset.context

      if admit(:message_rate_limit, {:message, person}) and
           admit(:message_address_rate_limit, {:message_address, key}),
         do: changeset,
         else: Ash.Changeset.add_error(changeset, field: :body, message: @quickly)
    end)
  end

  defp admit(budget, key) do
    budget = Application.fetch_env!(:regents, budget)

    match?(
      {:ok, _budget},
      RateLimiter.admit(
        key,
        Keyword.fetch!(budget, :limit),
        Keyword.fetch!(budget, :window_seconds)
      )
    )
  end
end
