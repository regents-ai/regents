defmodule Regents.Patchbay.Forum.SolutionAccept do
  @moduledoc """
  The asker of a paid priority report names the reply that answered it, and
  the money held for the report goes to that reply's author.

  Nothing a caller sends names the asker: the actor is whoever the door
  verified, a profile signed in on a page or the wallet that paid, proven by
  its signature. The report is held under a row lock while the reply is
  checked and marked, so two accepts arriving at once cannot both get
  through. The payout job commits with that mark and runs outside the database
  transaction.
  """

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.{ReleaseAcceptedBounty, Report}

  @doc """
  Accepts the answer and queues the payout in the same transaction. The report
  comes back with the accepted reply and its author loaded.
  """
  @spec run(String.t(), String.t() | nil, struct() | nil) ::
          {:ok, Report.t()} | {:error, term()}
  def run(report_id, reply_id, actor), do: accept(actor, report_id, reply_id)

  # The check and the mark happen under one row lock, so a second accept that
  # arrives while the first is being written waits for it and is then refused,
  # before anything reaches the chain.
  defp accept(actor, id, reply_id) do
    case Ash.transact([Report], fn -> mark(actor, id, reply_id) end) do
      {:ok, {:ok, accepted}} -> {:ok, accepted}
      {:error, failure} -> {:error, failure}
    end
  end

  defp mark(actor, id, reply_id) do
    with {:ok, report} <- locked_report(actor, id),
         {:ok, accepted} <-
           Forum.accept_reply(report, reply_id, actor: actor, load: [accepted_reply: [:author]]),
         {:ok, _job} <- Oban.insert(ReleaseAcceptedBounty.new_payout(accepted)) do
      {:ok, accepted}
    end
  end

  defp locked_report(actor, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> found_or_missing(Forum.lock_report(uuid, actor: actor))
      :error -> {:error, :not_found}
    end
  end

  defp found_or_missing({:ok, nil}), do: {:error, :not_found}
  defp found_or_missing({:ok, record}), do: {:ok, record}

  defp found_or_missing({:error, error}) do
    if missing?(error), do: {:error, :not_found}, else: {:error, error}
  end

  @doc "Whether an error means there is no such report."
  @spec missing?(term()) :: boolean()
  def missing?(%Ash.Error.Query.NotFound{}), do: true
  def missing?(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &missing?/1)
  def missing?(_error), do: false
end
