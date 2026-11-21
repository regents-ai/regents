defmodule Regents.Keyfleet.Code.Setup do
  @moduledoc """
  Makes one project's repository in the code store and records it
  (`Regents.Keyfleet.Code.Repository`). Queued when the project starts
  (`Regents.Keyfleet.Code.Changes.MakeRepository`), and again by an ask for a
  repository not made yet (`queue/1`, from `Regents.Keyfleet.Code.owner/1`). Making it
  again finds the one already made, so a run that fails part way is simply
  run again. A failed run tries again a minute later, up to `max_attempts` runs.
  A setup that gave up is queued again by the next ask, and that is saved
  with the site's errors (`Regents.Keyfleet.Code.StoreDownError`).

  A project can be deleted while its repository is being made. The record is
  kept in a transaction holding the project's row, so a delete either
  commits first and is seen here, and the repository just made is deleted
  again instead of kept, or commits after and its own job finds the record
  (`Regents.Keyfleet.Code.DeleteRepository`). No repository outlives its project.
  """
  use Oban.Worker,
    queue: :keyfleet_code_store,
    max_attempts: 20,
    unique: [keys: [:repository], period: :infinity, states: :incomplete]

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Code
  alias Regents.Keyfleet.Code.{NodeClient, Repository, StoreDownError}
  alias Regents.Keyfleet.Projects

  @impl Oban.Worker
  def backoff(%Oban.Job{}), do: 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"repository" => repository}}) do
    case Code.get_repository(repository, actor: %System{}) do
      {:ok, nil} -> make(repository)
      {:ok, _made} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp make(repository) do
    with {:ok, owner} <- NodeClient.create_repository(repository),
         {:ok, kept} <-
           Ash.transact([Projects.Project, Repository], fn -> keep(repository, owner) end) do
      if kept == :deleted, do: NodeClient.delete_repository(repository, owner), else: :ok
    end
  end

  defp keep(repository, owner) do
    case Projects.locked_project_of_repository!(repository, actor: %System{}) do
      %{state: :deleted} -> :deleted
      _project -> Code.record_repository!(repository, owner, actor: %System{})
    end
  end

  @doc """
  Queues the repository's setup unless it is queued already: `{:setting_up,
  seconds}` until its next run starts, 0 when it runs now; or
  `:setup_restarted` while a setup runs again after an earlier one gave up.
  The ask that starts it again saves that with the site's errors.
  """
  def queue(repository) do
    gave_up? = gave_up?(repository)
    job = Oban.insert!(new(%{repository: repository}))

    cond do
      not gave_up? ->
        {:setting_up, until_run(job)}

      job.conflict? ->
        :setup_restarted

      true ->
        StoreDownError.report(
          "Setting up the repository #{repository} gave up after #{job.max_attempts} tries; it starts again"
        )

        :setup_restarted
    end
  end

  defp gave_up?(repository) do
    Oban.Repo.exists?(
      Oban.config(),
      Oban.Job.query(worker: __MODULE__, state: :discarded, args: %{repository: repository})
    )
  end

  # A job just queued may carry no time yet: it runs now.
  defp until_run(%Oban.Job{scheduled_at: %DateTime{} = at}),
    do: max(DateTime.diff(at, DateTime.utc_now()), 0)

  defp until_run(%Oban.Job{}), do: 0
end
