defmodule Regents.Keyfleet.Proposals.Changes.LimitWords do
  @moduledoc """
  Holds each signed-in person, and each agent's wallet, to the saves of
  proposal words in `config :regents, :keyfleet_proposal_words_rate_limit`, counted by
  `Regents.RateLimiter`. A save past it is refused
  (`WordsLimitError`), and the proposal, a person's or an agent's, goes ahead
  without its words. An agent changing its address would start the
  API's per-address budget again, so it is counted by its wallet.
  """
  use Ash.Resource.Change

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Proposals.Errors.WordsLimitError
  alias Regents.RateLimiter

  @impl true
  def change(changeset, _opts, %{actor: %Human{human_account_id: account_id}}),
    do: Ash.Changeset.before_action(changeset, &limit(&1, account_id))

  def change(changeset, _opts, %{actor: %Agent{wallet_address: wallet}}),
    do: Ash.Changeset.before_action(changeset, &limit(&1, wallet))

  def change(changeset, _opts, _context), do: changeset

  defp limit(changeset, saver) do
    budget = Application.fetch_env!(:regents, :keyfleet_proposal_words_rate_limit)

    case RateLimiter.admit(
           {:proposal_words, saver},
           Keyword.fetch!(budget, :limit),
           Keyword.fetch!(budget, :window_seconds)
         ) do
      {:ok, _budget} ->
        changeset

      {:error, :rate_limited, budget} ->
        Ash.Changeset.add_error(changeset, WordsLimitError.exception(retry_after: budget.reset))
    end
  end
end
