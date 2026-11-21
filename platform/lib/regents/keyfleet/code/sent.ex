defmodule Regents.Keyfleet.Code.Sent do
  @moduledoc """
  Records the commits one push to a branch brought (`Regents.Keyfleet.Code.Commit`):
  those its new tip reaches and no earlier tip of any branch reaches. Queued
  in the transaction that records the push (`Regents.Keyfleet.Code.record_pushes/4`),
  so every recorded push to a branch is followed up. Pushes only add, so
  the commits a push brought never change, and a run that fails part way is
  simply run again: a commit already recorded keeps the push that sent it
  first. A failed run tries again a minute later, up to `max_attempts` runs.
  """
  use Oban.Worker, queue: :keyfleet_code_store, max_attempts: 20

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Code
  alias Regents.Keyfleet.Code.{Commit, NodeClient, Push}

  # The commits one page of history reads, and the most one push records.
  @page 1000
  @most 100_000

  @impl Oban.Worker
  def backoff(%Oban.Job{}), do: 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"push_id" => push_id}}) do
    with {:ok, %Push{} = push} <- Code.push(push_id, actor: %System{}),
         {:ok, repository} when is_binary(repository) <-
           Code.repository(push.fleet_id, push.project),
         {:ok, %{owner: owner}} <- Code.get_repository(repository, actor: %System{}),
         {:ok, tips} <-
           Code.tips_before(push.fleet_id, push.project, push.pushed_at, actor: %System{}) do
      record(push, repository, owner, Enum.map(tips, & &1.head), 0)
    else
      # The push, its project or its repository is gone, and the commits with it.
      {:ok, nil} -> :ok
      :not_found -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp record(_push, _repository, _owner, _earlier, skip) when skip >= @most, do: :ok

  defp record(push, repository, owner, earlier, skip) do
    options = [start: push.head, not: earlier, skip: skip, limit: @page, timeout: :job]

    with {:ok, %{commits: commits, more?: more?}} <-
           NodeClient.commits(repository, owner, options),
         :ok <- keep(push, commits) do
      if more?, do: record(push, repository, owner, earlier, skip + @page), else: :ok
    end
  end

  defp keep(_push, []), do: :ok

  defp keep(push, commits) do
    commits
    |> Enum.map(
      &%{fleet_id: push.fleet_id, project: push.project, hash: &1["hash"], push_id: push.id}
    )
    |> Ash.bulk_create(Commit, :record,
      actor: %System{},
      return_errors?: true,
      stop_on_error?: true
    )
    |> case do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end

  @doc """
  Queues the job for every push to a branch recorded before commits were.
  Each job leaves out what the earlier tips reach, so the jobs may run in any
  order and each commit still names the push that sent it first. Run once by
  hand on a release
  (`bin/keyfleet rpc 'Regents.Keyfleet.Code.Sent.backfill()'`), with the owner's go:
  it writes to the production database. `{:ok, jobs_queued}`.
  """
  def backfill do
    pushes = Code.branch_pushes!(actor: %System{})
    pushes |> Enum.map(&new(%{push_id: &1.id})) |> Oban.insert_all()
    {:ok, length(pushes)}
  end
end
