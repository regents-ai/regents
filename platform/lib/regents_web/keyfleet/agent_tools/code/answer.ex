defmodule RegentsWeb.Keyfleet.AgentTools.Code.Answer do
  @moduledoc """
  A project's code as an agent reads it, the same over its signed requests
  and as the Claude connector's tools (`RegentsWeb.Keyfleet.AgentTools.Code`): the
  changes sent lately to its repository, each with the address a workspace
  cites its commit by (`:pushes`); its history (`:commits`); one commit
  with what it changed (`:commit`), read as the commit page and the history
  page read them (`RegentsWeb.Keyfleet.WorkspacePage`); and one file at a commit,
  whole (`:file`). Git itself reaches the code
  through `RegentsWeb.Keyfleet.Plugs.CodeGateway`. Each answer is
  `{status, body, nil}`; `params` is the signed request's JSON, its body
  with the names in its address.
  """

  require Logger

  alias Regents.Account.Actors.{Agent, System}
  alias Regents.Keyfleet.{Code, Fleets, Projects}
  alias RegentsWeb.{Endpoint, NotFoundError}
  alias RegentsWeb.Keyfleet.{Refusal, WorkspacePage}

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) :: {pos_integer(), map(), nil}
  def answer(:pushes, %{"fleet_id" => fleet_id, "project" => project}, actor, _waiter) do
    with {:ok, %{}} <- Fleets.get_fleet(fleet_id, actor: %System{}),
         {:ok, pushes} <- Code.recent_pushes(fleet_id, project, actor: actor),
         {:project, {:ok, %{repository: repository}}} <-
           {:project, Projects.project(fleet_id, project, actor: actor)} do
      ok(%{
        pushes:
          for push <- pushes do
            %{
              ref: push.ref,
              commit: push.head,
              commit_url: WorkspacePage.commit_url(fleet_id, repository, push.head),
              token_id: push.token_id,
              pushed_at: push.pushed_at
            }
          end
      })
    else
      {:ok, nil} -> refusal(404, "fleet_unknown")
      {:project, {:ok, nil}} -> refusal(404, "project_unknown")
      {:project, failed} -> refused(fleet_id, failed)
      failed -> refused(fleet_id, failed)
    end
  end

  # The history's first page is {}; next names the page after it.
  def answer(:commits, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    case repository(fleet_id, params["project"]) do
      {:ok, repository} ->
        fleet_id
        |> WorkspacePage.history(repository, params["from"], Map.get(params, "page", 1), actor)
        |> case do
          %{members_only?: true} ->
            refused(fleet_id, {:error, %Ash.Error.Forbidden{}})

          %{commits: :unreadable} ->
            refusal(503, "code_unavailable")

          history ->
            ok(%{
              commits: Enum.map(history.commits, &history_commit(&1, fleet_id, repository)),
              head: history.head,
              next: if(history.more?, do: %{from: history.head, page: history.page + 1})
            })
        end

      {:refused, status, code} ->
        refusal(status, code)
    end
  rescue
    NotFoundError -> refusal(404, "history_page_unknown")
  end

  def answer(:commit, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    case repository(fleet_id, params["project"]) do
      {:ok, repository} ->
        fleet_id
        |> WorkspacePage.commit(repository, params["commit"], actor)
        |> case do
          %{members_only?: true} -> refused(fleet_id, {:error, %Ash.Error.Forbidden{}})
          %{change: :unreadable} -> refusal(503, "code_unavailable")
          %{change: :not_found} -> refusal(404, "commit_unknown")
          commit -> ok(commit_body(commit))
        end

      {:refused, status, code} ->
        refusal(status, code)
    end
  rescue
    NotFoundError -> refusal(404, "commit_unknown")
  end

  # Whoever may read the commit reads its files: the same rule as the
  # commit's own read (`Regents.Keyfleet.Code.Commit`, `:of_hashes`).
  def answer(:file, %{"fleet_id" => fleet_id, "commit" => hash} = params, actor, _waiter) do
    case repository(fleet_id, params["project"]) do
      {:ok, repository} ->
        fleet_id
        |> Code.commit_file(repository, hash, params["path"], actor)
        |> file_answer(fleet_id, repository, params)

      {:refused, status, code} ->
        refusal(status, code)
    end
  end

  defp file_answer({:ok, bytes}, fleet_id, repository, %{"commit" => hash, "path" => path}) do
    ok(%{
      commit: hash,
      commit_url: WorkspacePage.commit_url(fleet_id, repository, hash),
      path: path,
      content: bytes,
      size: byte_size(bytes),
      sha256: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
    })
  end

  defp file_answer({:too_large, size}, _fleet_id, _repository, _params) do
    {422,
     Refusal.body(
       "code_file_too_large",
       "code_file reads a file of at most #{Code.config()[:file_max_bytes]} bytes; " <>
         "this one has #{size}. Clone the project's repository to read it: " <>
         "projects_list gives its clone_url."
     ), nil}
  end

  defp file_answer(:not_text, _fleet_id, _repository, _params),
    do: refusal(422, "code_file_not_text")

  defp file_answer(:not_found, _fleet_id, _repository, _params), do: refusal(404, "file_unknown")

  defp file_answer(:forbidden, fleet_id, _repository, _params),
    do: refused(fleet_id, {:error, %Ash.Error.Forbidden{}})

  defp file_answer({:error, error}, _fleet_id, repository, _params) do
    Logger.warning("The repository #{repository} could not be read: #{reason(error)}")
    refusal(503, "code_unavailable")
  end

  defp ok(body), do: {200, body, nil}
  defp refusal(status, code), do: {status, Refusal.body(code), nil}

  defp repository(fleet_id, project) do
    case Fleets.get_fleet(fleet_id, actor: %System{}) do
      {:ok, %{}} ->
        case Code.repository(fleet_id, project) do
          {:ok, repository} when is_binary(repository) -> {:ok, repository}
          {:ok, nil} -> {:refused, 404, "project_unknown"}
          {:error, _error} -> {:refused, 503, "code_catching_up"}
        end

      {:ok, nil} ->
        {:refused, 404, "fleet_unknown"}
    end
  end

  defp history_commit(commit, fleet_id, repository) do
    %{
      commit: commit.hash,
      commit_url: WorkspacePage.commit_url(fleet_id, repository, commit.hash),
      subject: commit.subject,
      author: commit.author,
      written_at: commit.at,
      sent_by: sent_by(commit.sent),
      cited_by: Enum.map(commit.citing, &Map.take(&1, [:id, :type, :title]))
    }
  end

  defp commit_body(%{change: change} = commit) do
    %{
      commit: commit.hash,
      commit_url: commit.url,
      subject: change.subject,
      message: change.body,
      author: change.author,
      written_at: change.at,
      parents: Enum.map(change.parents, & &1.hash),
      sent_by: sent_by(commit.sent),
      files:
        for file <- change.files do
          %{
            path: file.path,
            old_path: file.old_path,
            status: file.status,
            additions: file.additions,
            deletions: file.deletions,
            binary: file.binary?,
            patch: file.patch,
            patch_truncated: file.cut?
          }
        end,
      files_truncated: change.files_cut?,
      files_url: Endpoint.url() <> commit.files_link,
      cited_by:
        for work <- commit.citing do
          %{
            id: work.id,
            type: work.type,
            title: work.title,
            archived: work.archived?,
            notebook_ref: work.notebook_ref,
            result_ref: work.result_ref
          }
        end
    }
  end

  defp sent_by(nil), do: nil

  defp sent_by(sent),
    do: %{token_id: sent.token_id, agent_name: sent.agent, ref: sent.ref, pushed_at: sent.at}

  defp refused(fleet_id, {:error, %Ash.Error.Forbidden{}}) do
    if Regents.Keyfleet.Chain.fresh?(fleet_id),
      do: refusal(403, "code_not_holder"),
      else: refusal(503, "ownership_refreshing")
  end

  defp refused(fleet_id, {:error, error}) do
    Regents.Keyfleet.Code.RecordsDownError.report(
      "The changes sent to the code of #{fleet_id} could not be read: " <>
        inspect(error.__struct__)
    )

    refusal(503, "code_catching_up")
  end

  defp reason(%module{}), do: inspect(module)
  defp reason(reason), do: inspect(reason)
end
