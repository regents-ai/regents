defmodule RegentsWeb.Keyfleet.AgentTools.Notebooks.Answer do
  @moduledoc """
  A fleet's notebooks and their runs as an agent uses them, the same over its
  signed requests and as the Claude connector's tools
  (`RegentsWeb.Keyfleet.AgentTools.Notebooks`): list the notebooks, each with the
  newest kept page of a run of it, whoever started it (`:list`), start a
  background run of a notebook's saved code (`:run`), then read it until it
  has finished and its saved result has an address the workspace can cite
  (`:result`, `Regents.Keyfleet.Notebooks.Runs`), and read what the notebook's newest
  kept run page holds (`:page`); make a notebook (`:create`), then
  list, read, add and write its files (`:files`, `:read_file`, `:add_file`,
  `:write_file`, `Regents.Keyfleet.Notebooks.Files`), each in the space of the
  project the address names; lock or unlock a notebook it made (`:lock`),
  and list and bring back the project's daily copies of its notebooks
  (`:copies`, `:restore`; `Regents.Keyfleet.Notebooks.lock/6`, `copies/4`,
  `restore/5`). Each answer is `{status, body, retry_after}`; `params` is the
  signed request's JSON, its body with the names in its address.

  The agent is let in exactly as on the fleet's notebook host
  (`Regents.Keyfleet.Notebooks.admit/3`), and the hub knows each run, notebook and
  change as the agent's. An archived project's notebooks are read and never
  changed, and a Key whose edits a vote of the fleet has restricted lists and
  reads, and starts, makes and writes nothing. Starting a run spends the
  agent's `:notebook_run_starts` allowance, the same one the notebook host
  spends. A file write names the revision it read, and one over a file
  changed since answers `stale_revision` with the file's revision now. A
  file add or write the hub was asked for and didn't answer is neither done
  nor refused: it answers `notebook_outcome_unknown`, with a receipt to
  settle it by.
  """

  alias Regents.Account.Actors.Agent
  alias Regents.Keyfleet.{Notebooks, Projects}
  alias Regents.Keyfleet.Notebooks.{Files, Runs}
  alias Regents.Keyfleet.Projects.Errors.ClosedError
  alias Regents.Limits
  alias RegentsWeb.Keyfleet.Refusal

  # What each operation needs: a read, or a change an archived project or a
  # restricted Key can't make.
  @changes [:run, :create, :add_file, :write_file, :lock, :restore]

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) ::
          {pos_integer(), map(), pos_integer() | nil}
  def answer(op, %{"fleet_id" => fleet_id, "project" => project} = params, actor, _waiter) do
    need = if op in @changes, do: :change, else: :read

    with {:hub, true} <- {:hub, Notebooks.hub?(fleet_id)},
         {:profile, {:ok, subject}} when is_binary(subject) <-
           {:profile, Notebooks.agent(actor)},
         {:ok, access} <- Notebooks.admit(actor, fleet_id, subject),
         {:restricted, false} <- {:restricted, need == :change and access.restricted?},
         :ok <- usable(fleet_id, project, need),
         {:space, space} when is_binary(space) <- {:space, access.spaces[project]},
         {:ok, body} <- run(op, params, actor, subject, space) do
      {200, body, nil}
    else
      {:hub, false} -> refusal(404, "notebooks_not_found")
      %ClosedError{} = closed -> closed(closed)
      {:error, %ClosedError{} = closed} -> closed(closed)
      {:restricted, true} -> refusal(403, "notebooks_edits_restricted")
      {:error, :edits_restricted} -> refusal(403, "notebooks_edits_restricted")
      {:error, :not_maker} -> refusal(403, "notebooks_maker_only")
      {:profile, {:ok, nil}} -> refusal(403, "notebooks_agent_profile")
      {:profile, {:error, _error}} -> refusal(503, "notebooks_unavailable")
      {:error, :not_holder} -> refusal(403, "notebooks_not_holder")
      {:error, :not_found} -> refusal(404, "notebook_run_not_found")
      {:error, :page_not_kept} -> refusal(404, "notebook_page_not_kept")
      {:error, :page_unreadable} -> refusal(422, "notebook_page_unreadable")
      {:error, :runs_full} -> refusal(429, "notebook_runs_full")
      {:error, :file_not_found} -> refusal(404, "notebook_file_not_found")
      {:error, :copy_not_found} -> refusal(404, "notebook_copy_not_found")
      {:error, :file_exists} -> refusal(409, "notebook_file_exists")
      {:error, :writes_paused} -> refusal(409, "notebook_writes_paused")
      {:error, {:stale_revision, current}} -> stale(current)
      {:error, :refused} -> refusal(422, "notebook_file_refused")
      {:error, :cursor_unknown} -> refusal(422, "notebook_cursor_unknown")
      {:error, :files_full} -> refusal(422, "notebook_files_full")
      {:error, :too_large} -> refusal(422, "notebook_file_too_large")
      {:error, :not_text} -> refusal(422, "notebook_file_not_text")
      {:error, :catching_up} -> refusal(503, "notebooks_catching_up")
      {:error, :setting_up} -> refusal(503, "notebooks_setting_up")
      {:space, nil} -> refusal(503, "notebooks_setting_up")
      {:error, :unavailable} -> refusal(503, "notebooks_unavailable")
      {:error, :unknown} -> unknown(params)
      # Runs started on the notebook host and here share one allowance.
      {:limited, seconds} -> {429, Refusal.body("notebook_runs_limit_reached"), seconds}
    end
  end

  defp run(:list, %{"fleet_id" => fleet_id} = params, _actor, subject, space),
    do: Runs.list(fleet_id, subject, space, params["cursor"])

  defp run(:run, %{"fleet_id" => fleet_id} = params, _actor, subject, space) do
    %{"notebook_id" => notebook_id, "idempotency_key" => idempotency_key} = params

    with :ok <- Limits.admit(:notebook_run_starts, subject),
         do: Runs.start(fleet_id, subject, space, notebook_id, idempotency_key)
  end

  defp run(:result, %{"fleet_id" => fleet_id} = params, _actor, subject, space),
    do: Runs.read(fleet_id, subject, space, params["notebook_id"], params["run_id"])

  defp run(:page, %{"fleet_id" => fleet_id} = params, _actor, subject, space),
    do: Runs.page(fleet_id, subject, space, params["notebook_id"])

  defp run(:create, %{"fleet_id" => fleet_id} = params, actor, subject, space) do
    notebook =
      params
      |> Map.take(~w(title code description))
      |> Map.put("tags", tags(params["goal"], params["folder"]))

    fleet_id
    |> Files.create(subject, space, notebook, params["idempotency_key"])
    |> edited(actor, fleet_id)
  end

  defp run(:files, %{"fleet_id" => fleet_id} = params, _actor, subject, space) do
    Files.list(fleet_id, subject, space, params["notebook_id"], params["path"], params["cursor"])
  end

  defp run(:read_file, %{"fleet_id" => fleet_id} = params, _actor, subject, space),
    do: Files.read(fleet_id, subject, space, params["notebook_id"], params["path"])

  defp run(:add_file, params, actor, subject, space),
    do: write(params, actor, subject, space, :add)

  defp run(:write_file, params, actor, subject, space),
    do: write(params, actor, subject, space, {:write, params["expected_revision"]})

  defp run(:lock, %{"fleet_id" => fleet_id} = params, actor, subject, _space) do
    %{"project" => project, "notebook_id" => notebook_id, "locked" => locked} = params

    with {:error, :not_found} <-
           Notebooks.lock(fleet_id, actor, subject, project, notebook_id, locked),
         do: {:error, :file_not_found}
  end

  defp run(:copies, %{"fleet_id" => fleet_id, "project" => project}, actor, subject, _space) do
    with {:ok, notebooks} <- Notebooks.copies(fleet_id, actor, subject, project),
         do: {:ok, %{notebooks: notebooks}}
  end

  defp run(:restore, %{"fleet_id" => fleet_id} = params, actor, subject, _space) do
    fleet_id
    |> Notebooks.restore(actor, subject, params["project"], params["copy_id"])
    |> edited(actor, fleet_id)
  end

  defp write(%{"fleet_id" => fleet_id} = params, actor, subject, space, mode) do
    %{"notebook_id" => notebook_id, "path" => path, "content" => content} = params

    fleet_id
    |> Files.write(actor, subject, space, notebook_id, path, content, mode)
    |> edited(actor, fleet_id)
  end

  # A notebook made or a file written is the agent's latest contribution.
  defp edited({:ok, _answer} = made, actor, fleet_id) do
    Regents.Keyfleet.Agents.record_contribution(actor, fleet_id, :notebook)
    made
  end

  defp edited(refused, _actor, _fleet_id), do: refused

  defp refusal(status, code), do: {status, Refusal.body(code), nil}

  # A write over a file changed since the revision it named: nothing was
  # written, and the file's revision now is the one to read and merge from.
  defp stale(current) do
    body =
      put_in(Refusal.body("stale_revision"), [:error, :details], %{current_revision: current})

    {409, body, nil}
  end

  # A file write the hub was asked for and didn't answer: the receipt names
  # what was sent, and reading the path back answers the same sha256 exactly
  # when it was written.
  defp unknown(%{"notebook_id" => notebook_id, "path" => path, "content" => content}) do
    receipt = %{
      request_id: Logger.metadata()[:request_id],
      notebook_id: notebook_id,
      path: path,
      sha256: Files.sha256(content),
      bytes: byte_size(content)
    }

    body =
      put_in(Refusal.body("notebook_outcome_unknown"), [:error, :details], %{
        receipt: receipt,
        settle: "notebooks_read_file"
      })

    {503, body, nil}
  end

  # An archived project's notebooks are read, and only an active project's
  # changed.
  defp usable(fleet_id, project, need) do
    case Projects.open(fleet_id, project) do
      {:ok, _project} -> :ok
      {:error, %ClosedError{code: :project_archived}} when need == :read -> :ok
      {:error, closed} -> closed
    end
  end

  defp closed(%ClosedError{code: code} = closed) do
    status = if code == :project_archived, do: 409, else: 404

    body =
      Refusal.closed(to_string(code), Exception.message(closed), %{
        project: closed.project,
        active: closed.active
      })

    {status, body, nil}
  end

  # A notebook made for goal#N carries the tag goal-N, which lists it on the
  # goal's page, and one made in a folder the tag folder/<name>, which the
  # project's Docs group it under.
  defp tags(goal, folder) do
    for {prefix, value} <- [{"goal-", goal_number(goal)}, {"folder/", folder}],
        value != nil,
        do: prefix <> value
  end

  defp goal_number(nil), do: nil
  defp goal_number("goal#" <> n), do: n
end
