defmodule Regents.Keyfleet.Code.DeleteRepository do
  @moduledoc """
  Deletes a deleted project's repository from the code store for good, then
  the site's record of it (`Regents.Keyfleet.Code.Repository`). Queued in the
  transaction that deletes the project (`Regents.Keyfleet.Projects.Changes.Forget`),
  once per repository. A repository the store never made has nothing to
  delete, and one already gone counts as deleted, so a run that fails part
  way is simply run again, a minute later, up to `max_attempts` runs.
  """
  use Oban.Worker,
    queue: :keyfleet_code_store,
    max_attempts: 20,
    unique: [keys: [:repository], period: :infinity, states: :incomplete]

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Code
  alias Regents.Keyfleet.Code.NodeClient

  @impl Oban.Worker
  def backoff(%Oban.Job{}), do: 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"repository" => repository}}) do
    case Code.get_repository(repository, actor: %System{}) do
      {:ok, nil} ->
        :ok

      {:ok, made} ->
        with :ok <- NodeClient.delete_repository(repository, made.owner),
             do: Code.forget_repository(made, actor: %System{})
    end
  end
end
