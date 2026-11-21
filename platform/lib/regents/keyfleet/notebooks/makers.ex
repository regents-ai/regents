defmodule Regents.Keyfleet.Notebooks.Makers do
  @moduledoc """
  Who made each thing in a fleet's notebooks. Sean, 21 Oct 2026: members
  open, copy and run each other's work, and only whoever made a thing
  removes, changes or stops it.

  The hub keeps who made most things, and is asked as the member checking
  (`Regents.Keyfleet.Notebooks.MemberRequest`): a notebook's author, who started a
  session, who made a job, who started a run. A saved result's maker is its
  notebook's author for a version's page and whoever started the run for a
  run's page. Who added a workspace file or folder is kept here
  (`Regents.Keyfleet.Notebooks.FileMaker`); a path with no maker kept is the
  notebook's author's.

  Each check is `:ok` for the maker, or `{:error, reason}`: `:not_maker`,
  `:not_found` when the hub doesn't have the thing, or `:unavailable` when
  the hub or the kept makers can't be read.

  Sean, 27 Oct 2026: a notebook's creator locks or unlocks it. Locked, as
  every notebook starts, the rule above stands; unlocked, every member also
  changes what is in it, and still only its creator deletes it or locks it
  again (`open_to?/4`). A Key's scratchpad is made by this site
  (`Regents.Keyfleet.Notebooks.Scratchpads`), and its creator is whoever acts as that
  Key.
  """

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Graph.Checks.KeyActor
  alias Regents.Keyfleet.Graph.Errors.{EditsRestrictedError, NotKeyHolderError}
  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.{FileMaker, RecordsDownError, Runs}

  import Regents.Keyfleet.Notebooks.MemberRequest

  # The hub lists at most this many workspace entries a page.
  @page 500

  @doc """
  Whether the notebook is open to `actor` past the checks below, as
  `{:ok, boolean}`, or `{:error, :unavailable}` when that can't be read now.
  `:edit` asks whether `actor` may change what is in it, as every member may
  once its creator unlocked it; `:creator` whether `actor` is its creator by
  Keyfleet's own record, as whoever acts as the Key whose scratchpad it is
  (`Regents.Keyfleet.Notebooks.Setting`). Any other notebook's creator is its author
  in the hub, whom `notebook/4` asks.
  """
  def open_to?(fleet_id, actor, notebook_id, scope) when scope in [:edit, :creator] do
    case Notebooks.notebook_setting(fleet_id, notebook_id, actor: %System{}) do
      {:ok, %{unlocked: true}} when scope == :edit -> {:ok, true}
      {:ok, %{key: key}} when is_integer(key) -> acts_as(actor, fleet_id, key)
      {:ok, _locked} -> {:ok, false}
      {:error, error} -> down("read", fleet_id, notebook_id, error)
    end
  end

  @doc """
  Whether `actor` acts as the fleet's Key `key` now (`KeyActor`), as
  `{:ok, boolean}`, or `{:error, :unavailable}` when that can't be read.
  """
  def acts_as(actor, fleet_id, key) do
    within = Application.fetch_env!(:regents, :keyfleet_graph)[:check_timeout]

    case KeyActor.command(actor, fleet_id, key, nil, within) do
      {:ok, _command} -> {:ok, true}
      {:error, %NotKeyHolderError{}} -> {:ok, false}
      {:error, %EditsRestrictedError{}} -> {:ok, false}
      {:error, _error} -> {:error, :unavailable}
    end
  end

  @doc "Whether `subject` made the notebook."
  def notebook(fleet_id, subject, project_id, notebook_id) do
    fleet_id
    |> request(subject, :get, notebook_path(project_id, notebook_id))
    |> made_by(subject, &get_in(&1, ["meta", "author"]))
  end

  @doc "Whether `subject` started the session."
  def session(fleet_id, subject, project_id, notebook_id, session_id) do
    path = "#{notebook_path(project_id, notebook_id)}/sessions/#{segment(session_id)}"
    fleet_id |> request(subject, :get, path) |> made_by(subject, & &1["user_id"])
  end

  @doc "Whether `subject` made the job."
  def job(fleet_id, subject, project_id, notebook_id, job_id) do
    path = "#{notebook_path(project_id, notebook_id)}/jobs/#{segment(job_id)}"
    fleet_id |> request(subject, :get, path) |> made_by(subject, & &1["created_by"])
  end

  @doc "Whether `subject` started the run."
  def run(fleet_id, subject, project_id, notebook_id, job_id, run_id) do
    path =
      "#{notebook_path(project_id, notebook_id)}/jobs/#{segment(job_id)}/runs/#{segment(run_id)}"

    fleet_id |> request(subject, :get, path) |> made_by(subject, & &1["triggered_by"])
  end

  @doc """
  Whether `subject` made the saved result of `source_id`: a version's
  (`ver_…`) is its notebook's author's, a run's (`run_…`) whoever started it.
  The notebook is looked for in each of the fleet's spaces in turn.
  """
  def result(fleet_id, subject, notebook_id, source_id) do
    with {:ok, _project} <- result_project(fleet_id, subject, notebook_id, source_id), do: :ok
  end

  @doc """
  The project whose notebook holds the saved result `subject` made, as
  `{:ok, project}`, by the same rule and with the same refusals as
  `result/4`.
  """
  def result_project(fleet_id, subject, notebook_id, source_id) do
    case Notebooks.spaces(fleet_id) do
      {:ok, spaces} -> find_result(spaces, fleet_id, subject, notebook_id, source_id)
      {:error, _error} -> {:error, :unavailable}
    end
  end

  defp find_result([], _fleet_id, _subject, _notebook_id, _source_id), do: {:error, :not_found}

  defp find_result([{project, space} | spaces], fleet_id, subject, notebook_id, source_id) do
    case result_in(fleet_id, subject, space, notebook_id, source_id) do
      :ok -> {:ok, project}
      {:error, :not_found} -> find_result(spaces, fleet_id, subject, notebook_id, source_id)
      error -> error
    end
  end

  defp result_in(fleet_id, subject, project_id, notebook_id, "run_" <> _ = run_id),
    do: result_run(fleet_id, subject, project_id, notebook_id, run_id)

  defp result_in(fleet_id, subject, project_id, notebook_id, _version),
    do: notebook(fleet_id, subject, project_id, notebook_id)

  defp result_run(fleet_id, subject, project_id, notebook_id, run_id) do
    with {:ok, _path, run} <- Runs.find(fleet_id, subject, project_id, notebook_id, run_id) do
      if run["triggered_by"] == subject, do: :ok, else: {:error, :not_maker}
    end
  end

  defp made_by({:ok, %Req.Response{status: 200, body: %{"data" => data}}}, subject, maker),
    do: if(maker.(data) == subject, do: :ok, else: {:error, :not_maker})

  defp made_by({:ok, %Req.Response{status: 404}}, _subject, _maker), do: {:error, :not_found}
  defp made_by(_answer, _subject, _maker), do: {:error, :unavailable}

  ## Workspace files

  @doc """
  The path the hub keeps a workspace file under, for the `path` a request
  names: `{:ok, key}`, the path without its one leading `/`, or `:error` for
  any other spelling of a path (an empty, `.` or `..` part, a backslash or a
  NUL), so each file has one key and one maker.
  """
  def file_key("/" <> path), do: key(path)
  def file_key(path), do: key(path)

  @doc "The path the hub keeps a folder under, as `file_key/1`, with one trailing `/` allowed."
  def folder_key(path), do: path |> String.replace_suffix("/", "") |> file_key()

  defp key(path) do
    if String.valid?(path) and not String.contains?(path, ["\\", <<0>>]) and
         Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."])),
       do: {:ok, path},
       else: :error
  end

  @doc "Whether `subject` may write over the file at `key`: its maker may."
  def overwrite(fleet_id, subject, project_id, notebook_id, key) do
    with {:ok, makers} <- kept_makers(fleet_id, notebook_id, key) do
      case makers do
        %{^key => ^subject} -> :ok
        %{^key => _other} -> {:error, :not_maker}
        _none -> notebook(fleet_id, subject, project_id, notebook_id)
      end
    end
  end

  @doc """
  Whether `subject` may remove `key` and everything under it: they made each
  file under it, and each folder with nothing in it, or the file itself.
  """
  def removal(fleet_id, subject, project_id, notebook_id, key) do
    with {:ok, leaves} <- leaves(fleet_id, subject, project_id, notebook_id, key),
         {:ok, makers} <- kept_makers(fleet_id, notebook_id, key) do
      cond do
        Enum.any?(leaves, &(Map.get(makers, &1, subject) != subject)) -> {:error, :not_maker}
        Enum.all?(leaves, &Map.has_key?(makers, &1)) -> :ok
        true -> notebook(fleet_id, subject, project_id, notebook_id)
      end
    end
  end

  @doc """
  Whether the file at `key` is free for `subject` to be kept as its maker:
  `{:ok, true}` when no maker is kept for it, or `subject` is.
  """
  def unclaimed?(fleet_id, notebook_id, key, subject) do
    with {:ok, makers} <- kept_makers(fleet_id, notebook_id, key),
         do: {:ok, Map.get(makers, key, subject) == subject}
  end

  @doc "Keeps `subject` as the maker of the file or folder at `key`."
  def record(fleet_id, notebook_id, key, subject) do
    case Notebooks.record_file_maker(fleet_id, notebook_id, key, subject, actor: %System{}) do
      {:ok, _maker} -> :ok
      {:error, error} -> down("kept", fleet_id, notebook_id, error)
    end
  end

  @doc """
  Keeps `subject` as the maker of the file they just added new at `key`;
  when that can't be kept, removes it from the hub again, so it never stays
  as the notebook maker's, answering `{:error, :unavailable}` once it is gone,
  or `{:error, :unknown}` when the hub doesn't say so and it may still be
  there. A folder is never removed this way: the hub may answer for one that
  was there already, with other members' files in it.
  """
  def record_added(fleet_id, subject, project_id, notebook_id, key) do
    with {:error, :unavailable} <- record(fleet_id, notebook_id, key, subject) do
      fleet_id
      |> request(
        subject,
        :delete,
        notebook_path(project_id, notebook_id) <> "/workspace/entries",
        params: [path: key]
      )
      |> removed()
    end
  end

  defp removed({:ok, %Req.Response{status: status}}) when status in 200..299 or status == 404,
    do: {:error, :unavailable}

  defp removed(_answer), do: {:error, :unknown}

  @doc "Forgets the makers of `key` and everything under it, once they are removed."
  def forget(fleet_id, notebook_id, key) do
    FileMaker
    |> Ash.Query.for_read(
      :at_or_under,
      %{fleet_id: fleet_id, notebook_id: notebook_id, path: key},
      actor: %System{}
    )
    |> Ash.bulk_destroy(:forget, %{}, actor: %System{}, strategy: :atomic, notify?: false)
    |> case do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> down("forgotten", fleet_id, notebook_id, errors)
    end
  end

  defp kept_makers(fleet_id, notebook_id, key) do
    case Notebooks.file_makers_at_or_under(fleet_id, notebook_id, key, actor: %System{}) do
      {:ok, rows} -> {:ok, Map.new(rows, &{&1.path, &1.maker})}
      {:error, error} -> down("read", fleet_id, notebook_id, error)
    end
  end

  @doc """
  Reports that what Keyfleet keeps of a notebook could not be `what` (read,
  kept, forgotten), answering `{:error, :unavailable}`.
  """
  def down(what, fleet_id, notebook_id, error) do
    RecordsDownError.report(
      "What Keyfleet keeps of notebook #{notebook_id} in #{fleet_id} could not be #{what}: " <>
        inspect(error)
    )

    {:error, :unavailable}
  end

  # Each file under `key`, and each folder there with nothing in it; `key`
  # itself when nothing is under it (a file, or an empty folder).
  defp leaves(fleet_id, subject, project_id, notebook_id, key) do
    case under(fleet_id, subject, project_id, notebook_id, key) do
      {:ok, []} -> {:ok, [key]}
      found -> found
    end
  end

  # The hub names each entry from the workspace's root, `/` first; its key
  # is that path without the `/`, as the makers kept here are.
  defp under(fleet_id, subject, project_id, notebook_id, folder) do
    with {:ok, items} <- entries(fleet_id, subject, project_id, notebook_id, folder, nil, []) do
      Enum.reduce_while(items, {:ok, []}, fn
        %{"kind" => "directory", "path" => "/" <> key}, {:ok, leaves} ->
          fleet_id |> leaves(subject, project_id, notebook_id, key) |> add_found(leaves)

        %{"path" => "/" <> key}, {:ok, leaves} ->
          {:cont, {:ok, [key | leaves]}}

        _entry, _leaves ->
          {:halt, {:error, :unavailable}}
      end)
    end
  end

  defp add_found({:ok, found}, leaves), do: {:cont, {:ok, found ++ leaves}}
  defp add_found(error, _leaves), do: {:halt, error}

  defp entries(fleet_id, subject, project_id, notebook_id, folder, cursor, items) do
    params = [path: folder, limit: @page] ++ if(cursor, do: [cursor: cursor], else: [])

    case request(
           fleet_id,
           subject,
           :get,
           notebook_path(project_id, notebook_id) <> "/workspace/entries",
           params: params
         ) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"items" => page} = data}}} ->
        case data["cursor"] do
          nil -> {:ok, page ++ items}
          next -> entries(fleet_id, subject, project_id, notebook_id, folder, next, page ++ items)
        end

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      _answer ->
        {:error, :unavailable}
    end
  end
end
