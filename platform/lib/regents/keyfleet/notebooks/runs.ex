defmodule Regents.Keyfleet.Notebooks.Runs do
  @moduledoc """
  A fleet's notebooks, and background runs of them, that an agent lists,
  starts and reads through its own signed requests to this site
  (`RegentsWeb.Keyfleet.AgentNotebookController`), so it never signs a request for
  the notebook host itself.

  The hub is asked as the agent (`Regents.Keyfleet.Notebooks.MemberRequest`), so a
  run is the agent's, in its own job for the notebook, "Agent runs", made the
  first time it starts a run there. A run works through the notebook's saved
  code, top to bottom, in a fresh sandbox, and never changes the notebook.

  Reading a finished run keeps its page and answers the saved result's
  address (`Regents.Keyfleet.Notebooks.result_url/4`), as reading that page on the
  notebook host does (`RegentsWeb.Keyfleet.Plugs.NotebookGateway`): an address is
  never handed out for a page Keyfleet hasn't kept.

  A run answers the hub's `failure` as the hub gave it to the agent: where a
  failed or timed-out run stopped, and, when the agent started the run or
  wrote the notebook, the last lines of that step's output with secrets
  removed. Its page's copy records where it stopped and why, never those
  lines (`Regents.Keyfleet.Notebooks.record_run_failure/3`).

  Listing the notebooks keeps no page and asks the hub only for the page of
  notebooks: each one's `state` is the newest page Keyfleet keeps of a
  background run of it, whoever started the run, read from Keyfleet's copies
  alone (`Regents.Keyfleet.Notebooks.SavedOutput`): whether that run worked, how it
  failed if it did, and whether the notebook was changed after the page was
  made.

  Reading a notebook's page keeps nothing and changes nothing: it answers
  what that same newest kept run page holds (`Regents.Keyfleet.Notebooks.Page`), once
  the hub has answered the notebook to the agent in the project's space.

  A run started here records what it ran from (`Regents.Keyfleet.Notebooks.RunSource`):
  the sha256 of the notebook's saved code just before it started, and every
  file of it then with its revision (`Regents.Keyfleet.Notebooks.Files.manifest/4`).
  Reading the run answers that `source`; once the run has finished,
  `entry_current`, whether the notebook's saved code is still that code, and
  `bundle_current`, whether every file is still as it was, nil when that
  can't be told; and while the run hasn't succeeded, `last_succeeded`, the
  newest kept page of a run of the notebook that succeeded, so no number of
  later failed or waiting runs hides the last good result.

  Each answer is `{:ok, run}`, with the notebook, the run and its status and,
  once its page is kept, `result_url`, or `{:ok, page}` for a listing; or
  `{:error, reason}`: `:not_found` for a notebook or run the hub doesn't
  have, `:runs_full` when the notebook takes no more runs for now,
  `:cursor_unknown` for a listing's cursor the hub doesn't take,
  `:page_not_kept` or `:page_unreadable` for a notebook's page Keyfleet
  doesn't keep or can't read, or `:unavailable` when the hub didn't answer or
  the kept pages couldn't be read.
  """

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.{Files, Page, RecordsDownError, SavedOutput}

  import Regents.Keyfleet.Notebooks.MemberRequest

  @job "Agent runs"
  # The most jobs a notebook holds on the hub, so one page lists them all.
  @jobs 100
  # A finished run has made its page, unless it was cancelled or skipped.
  @with_page ~w(succeeded failed timed_out)
  @finished ["cancelled" | @with_page]
  # A listing names at most this many notebooks a page.
  @page 50

  @doc """
  A page of the fleet's notebooks, newest first, as `subject`, from `cursor`,
  or from the newest when it is nil: `notebooks`, each with its title,
  description and when it was added, as the Docs place lists them; its
  address (`Regents.Keyfleet.Notebooks.notebook_url/3`); and its `state`, the newest
  page Keyfleet keeps of a background run of it, whoever started the run, or
  nil when it keeps none. Beside them, the `cursor` that names the next page,
  or nil after the last, and `has_more`, whether there is one.
  """
  def list(fleet_id, subject, project_id, cursor) do
    params = Enum.reject([cursor: cursor, limit: @page], &is_nil(elem(&1, 1)))

    with {:ok, %{"items" => notebooks} = page} <-
           fleet_id
           |> request(subject, :get, "/api/v1/projects/#{segment(project_id)}/notebooks",
             params: params
           )
           |> page_answer(),
         {:ok, pages} <- newest_run_pages(fleet_id, Enum.map(notebooks, & &1["id"])) do
      locks = Notebooks.locks(fleet_id)
      next = page["next_cursor"]

      {:ok,
       %{
         notebooks: Enum.map(notebooks, &listing(&1, fleet_id, project_id, pages, locks)),
         cursor: next,
         has_more: next != nil
       }}
    end
  end

  # The listing asks only for the cursor it is given, so a refusal is of the
  # cursor: one the hub never answered.
  defp page_answer({:ok, %Req.Response{status: status}}) when status in [400, 422],
    do: {:error, :cursor_unknown}

  defp page_answer(response), do: answer(response, 200)

  @doc """
  `notebook_id`'s page as `subject`: the newest page Keyfleet keeps of a
  background run of it, whoever started the run, read once the hub has
  answered the notebook to `subject` in the project's space. Answers the
  page's run, how that run went, the page's address, size and sha256, and
  its cells (`Regents.Keyfleet.Notebooks.Page`), all within `page_answer_max_bytes`
  of JSON.
  """
  def page(fleet_id, subject, project_id, notebook_id) do
    with {:ok, _notebook} <-
           fleet_id
           |> request(subject, :get, notebook_path(project_id, notebook_id))
           |> answer(200),
         {:ok, pages} <-
           newest_run_pages(fleet_id, [notebook_id],
             query: Ash.Query.select(SavedOutput, [:page])
           ),
         do: held(pages[notebook_id], fleet_id)
  end

  defp held(nil, _fleet_id), do: {:error, :page_not_kept}

  defp held(kept, fleet_id) do
    config = Notebooks.config()

    facts =
      kept
      |> kept_run(fleet_id)
      |> Map.merge(%{
        notebook_id: kept.notebook_id,
        size: byte_size(kept.page),
        sha256: sha256(kept.page)
      })

    room =
      config[:page_answer_max_bytes] -
        byte_size(Jason.encode!(Map.merge(facts, %{cells: [], truncated: false})))

    case Page.read(kept.page, room, config[:page_value_max_bytes]) do
      {:ok, cells, truncated} -> {:ok, Map.merge(facts, %{cells: cells, truncated: truncated})}
      {:error, :unreadable} -> {:error, :page_unreadable}
    end
  end

  @doc """
  Starts a run of `notebook_id`'s saved code as `subject`, recording what it
  runs from. For a day the same `idempotency_key` answers that run again,
  even one sent before the first has answered: the hub looks the key up,
  starts the run and records it under the job's claim. Until the agent's job
  for the notebook exists, two sent at once can each make a job
  (`create_job/3`) and start a run in it.
  """
  def start(fleet_id, subject, project_id, notebook_id, idempotency_key) do
    notebook = notebook_path(project_id, notebook_id)

    with {:ok, %{"code" => code}} <-
           fleet_id |> request(subject, :get, notebook <> "/content") |> answer(200),
         {:ok, manifest} <- Files.manifest(fleet_id, subject, project_id, notebook_id),
         {:ok, job_id} <- job(fleet_id, subject, notebook),
         {:ok, run} <-
           fleet_id
           |> request(subject, :post, "#{notebook}/jobs/#{segment(job_id)}/runs",
             json: %{},
             headers: [{"idempotency-key", idempotency_key}]
           )
           |> answer(201) do
      source = record_source(fleet_id, notebook_id, run["run_id"], code, manifest)

      {:ok,
       notebook_id
       |> view(run, nil)
       |> Map.merge(%{
         source: source,
         entry_current: nil,
         bundle_current: nil,
         last_succeeded: nil
       })}
    end
  end

  @doc """
  Reads run `run_id` of `notebook_id` as `subject`, in whichever of the
  notebook's jobs it is, and once it has finished with a page, keeps that
  page and answers its address. A page already kept is answered as it is, so
  a finished run's page is fetched from the hub once.
  """
  def read(fleet_id, subject, project_id, notebook_id, run_id) do
    with {:ok, run_path, run} <- find(fleet_id, subject, project_id, notebook_id, run_id),
         {:ok, result_url} <- result_url(fleet_id, subject, notebook_id, run_id, run, run_path),
         {:ok, source} <- source(fleet_id, run_id),
         {:ok, current} <- current(fleet_id, subject, project_id, notebook_id, source, run),
         {:ok, last} <- last_succeeded(fleet_id, notebook_id, run) do
      {:ok,
       notebook_id
       |> view(run, result_url)
       |> Map.merge(current)
       |> Map.merge(%{source: source, last_succeeded: last})}
    end
  end

  @doc """
  Run `run_id` of `notebook_id` as `subject`, in whichever of the notebook's
  jobs it is: `{:ok, run_path, run}`.
  """
  def find(fleet_id, subject, project_id, notebook_id, run_id) do
    notebook = notebook_path(project_id, notebook_id)

    with {:ok, %{"items" => jobs}} <-
           fleet_id
           |> request(subject, :get, notebook <> "/jobs", params: [limit: @jobs])
           |> answer(200),
         do: find_run(fleet_id, subject, notebook, own_first(jobs, subject), run_id)
  end

  # The agent's own jobs are asked first: most runs it reads are its own.
  defp own_first(jobs, subject), do: Enum.sort_by(jobs, &(&1["created_by"] != subject))

  # The agent's own job for its runs of the notebook, so only it stops them
  # (`Regents.Keyfleet.Notebooks.Makers`).
  defp job(fleet_id, subject, notebook) do
    with {:ok, %{"items" => jobs}} <-
           fleet_id
           |> request(subject, :get, notebook <> "/jobs", params: [limit: @jobs])
           |> answer(200) do
      case own_job(jobs, subject) do
        %{"id" => id} -> {:ok, id}
        nil -> create_job(fleet_id, subject, notebook)
      end
    end
  end

  defp own_job(jobs, subject),
    do: Enum.find(jobs, &(&1["name"] == @job and &1["created_by"] == subject))

  # Runs start only when asked, and several may wait at once.
  defp create_job(fleet_id, subject, notebook) do
    with {:ok, %{"id" => id}} <-
           fleet_id
           |> request(subject, :post, notebook <> "/jobs",
             json: %{name: @job, concurrency_policy: "allow"},
             headers: [{"idempotency-key", "keyfleet-agent-runs:" <> subject}]
           )
           |> answer(201) do
      {:ok, id}
    end
  end

  # The runs' kept pages, read at once, by notebook and run. Of two copies of
  # one run's page, the newer is its saved result. A failed read is saved
  # with the site's errors (`Regents.Keyfleet.Notebooks.RecordsDownError`).
  defp result_urls(fleet_id, runs) do
    run_ids = for %{"run_id" => run_id} <- runs, do: run_id

    case Notebooks.saved_outputs(fleet_id, run_ids, actor: %System{}) do
      {:ok, kept} ->
        {:ok,
         kept
         |> Enum.sort_by(& &1.saved_at)
         |> Map.new(fn copy ->
           {{copy.notebook_id, copy.source_id},
            Notebooks.result_url(fleet_id, copy.notebook_id, copy.source_id, copy.saved_at)}
         end)}

      {:error, error} ->
        RecordsDownError.report(
          "The kept pages of #{fleet_id}'s notebook listing could not be read: " <>
            inspect(error.__struct__)
        )

        {:error, :unavailable}
    end
  end

  # The newest kept page of each of `notebook_ids`' runs that succeeded, by
  # notebook, as `%{run_id, result_url}`. A failed read is saved with the
  # site's errors.
  defp last_good_pages(fleet_id, notebook_ids) do
    case Notebooks.last_succeeded_outputs(fleet_id, notebook_ids, actor: %System{}) do
      {:ok, kept} ->
        {:ok,
         Map.new(kept, fn copy ->
           {copy.notebook_id,
            %{
              run_id: copy.source_id,
              result_url:
                Notebooks.result_url(fleet_id, copy.notebook_id, copy.source_id, copy.saved_at)
            }}
         end)}

      {:error, error} ->
        RecordsDownError.report(
          "The last good pages of #{fleet_id}'s notebooks could not be read: " <>
            inspect(error.__struct__)
        )

        {:error, :unavailable}
    end
  end

  # The newest kept page of each of `notebook_ids`' background runs, by
  # notebook, in one read that loads a page's bytes only when `options`
  # select them. A failed read is saved with the site's errors.
  defp newest_run_pages(fleet_id, notebook_ids, options \\ []) do
    case Notebooks.newest_run_outputs(fleet_id, notebook_ids, [actor: %System{}] ++ options) do
      {:ok, kept} ->
        {:ok, Map.new(kept, &{&1.notebook_id, &1})}

      {:error, error} ->
        RecordsDownError.report(
          "The newest run pages of #{fleet_id}'s notebooks could not be read: " <>
            inspect(error.__struct__)
        )

        {:error, :unavailable}
    end
  end

  # A notebook with nothing kept of it is locked and nobody's scratchpad.
  defp listing(notebook, fleet_id, project_id, pages, locks) do
    lock = Map.get(locks, notebook["id"], %{locked: true, key: nil})

    %{
      notebook_id: notebook["id"],
      title: notebook["title"],
      description: notebook["description"],
      created_at: notebook["created_at"],
      locked: lock.locked,
      scratchpad_key: lock.key,
      notebook_url: Notebooks.notebook_url(fleet_id, project_id, notebook["id"]),
      state: state(pages[notebook["id"]], notebook, fleet_id)
    }
  end

  # How the notebook's newest kept run page went, and whether the notebook
  # was changed after the hub made it (`Regents.Keyfleet.Notebooks.changed_since?/2`).
  defp state(nil, _notebook, _fleet_id), do: nil

  defp state(page, notebook, fleet_id) do
    page
    |> kept_run(fleet_id)
    |> Map.put(:changed_since, Notebooks.changed_since?(notebook["updated_at"], page))
  end

  # Which run made a kept page, whether it worked and where it stopped if
  # that is known, when the page was made, and its address.
  defp kept_run(page, fleet_id) do
    %{
      run_id: page.source_id,
      worked: page.succeeded,
      saved_at: DateTime.from_unix!(page.saved_at, :millisecond),
      error: page.failure,
      result_url: Notebooks.result_url(fleet_id, page.notebook_id, page.source_id, page.saved_at)
    }
  end

  # What the run ran from, as recorded the moment it started; nil when the
  # record couldn't be written, which is saved with the site's errors.
  defp record_source(fleet_id, notebook_id, run_id, code, manifest) do
    recorded =
      Notebooks.record_run_source(
        fleet_id,
        run_id,
        notebook_id,
        sha256(code),
        manifest.files,
        manifest.complete,
        actor: %System{}
      )

    with {:ok, _recorded} <- recorded,
         {:ok, source} <- source(fleet_id, run_id) do
      source
    else
      {:error, :unavailable} ->
        nil

      {:error, error} ->
        RecordsDownError.report(
          "What #{fleet_id}'s run #{run_id} ran from could not be recorded: " <>
            inspect(error.__struct__)
        )

        nil
    end
  end

  defp source(fleet_id, run_id) do
    case Notebooks.run_source(fleet_id, run_id, actor: %System{}) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, source} ->
        {:ok,
         %{
           started_at: source.started_at,
           code_sha256: source.code_sha256,
           files: source.files,
           files_complete: source.files_complete
         }}

      {:error, error} ->
        RecordsDownError.report(
          "What #{fleet_id}'s run #{run_id} ran from could not be read: " <>
            inspect(error.__struct__)
        )

        {:error, :unavailable}
    end
  end

  # Whether a finished run's notebook still holds what it ran from: its entry
  # code (`entry_current`), and every file of it (`bundle_current`, nil when
  # that can't be told).
  defp current(fleet_id, subject, project_id, notebook_id, %{} = source, %{"status" => status})
       when status in @finished do
    with {:ok, %{"code" => code}} <-
           fleet_id
           |> request(subject, :get, notebook_path(project_id, notebook_id) <> "/content")
           |> answer(200),
         {:ok, now} <- Files.manifest(fleet_id, subject, project_id, notebook_id) do
      entry_current = sha256(code) == source.code_sha256

      {:ok,
       %{entry_current: entry_current, bundle_current: entry_current and same_files(source, now)}}
    end
  end

  defp current(_fleet_id, _subject, _project_id, _notebook_id, _source, _run),
    do: {:ok, %{entry_current: nil, bundle_current: nil}}

  # Whether the files a run ran from are the notebook's files now, by path
  # and revision (a file's revision changes whenever its bytes do). A side is
  # whole when it holds every file, each with a revision; a side that isn't
  # gives no evidence of which files there are. So: false when a file both
  # sides list has another revision, or both sides are whole and differ;
  # true when both are whole and the same; otherwise nil. Recorded files come
  # back from the database with string keys.
  defp same_files(source, now) do
    ran = Map.new(source.files, &{&1["path"], &1["revision"]})
    kept = Map.new(now.files, &{&1.path, &1.revision})

    cond do
      revised?(ran, kept) -> false
      whole?(ran, source.files_complete) and whole?(kept, now.complete) -> ran == kept
      true -> nil
    end
  end

  defp revised?(ran, kept) do
    Enum.any?(ran, fn {path, revision} ->
      revision != nil and Map.get(kept, path) not in [nil, revision]
    end)
  end

  defp whole?(files, complete), do: complete and nil not in Map.values(files)

  # The notebook's last good page, beside a run that hasn't succeeded.
  defp last_succeeded(_fleet_id, _notebook_id, %{"status" => "succeeded"}), do: {:ok, nil}

  defp last_succeeded(fleet_id, notebook_id, _run) do
    with {:ok, good} <- last_good_pages(fleet_id, [notebook_id]), do: {:ok, good[notebook_id]}
  end

  defp sha256(code), do: :sha256 |> :crypto.hash(code) |> Base.encode16(case: :lower)

  # Each job is asked in turn until one has the run.
  defp find_run(fleet_id, subject, notebook, jobs, run_id) do
    Enum.reduce_while(jobs, {:error, :not_found}, fn %{"id" => job_id}, not_found ->
      path = "#{notebook}/jobs/#{segment(job_id)}/runs/#{segment(run_id)}"

      case fleet_id |> request(subject, :get, path) |> answer(200) do
        {:ok, run} -> {:halt, {:ok, path, run}}
        {:error, :not_found} -> {:cont, not_found}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # A finished run's kept page, kept now if it isn't yet, with how the run
  # failed if it did; nil while the run has no page.
  defp result_url(fleet_id, subject, notebook_id, run_id, %{"status" => status} = run, run_path)
       when status in @with_page do
    with {:ok, kept} <- result_urls(fleet_id, [%{"run_id" => run_id}]) do
      url =
        kept[{notebook_id, run_id}] ||
          keep_page(fleet_id, subject, notebook_id, run_id, run_path <> "/html")

      if url, do: Notebooks.record_run_failure(fleet_id, run_id, run["failure"])
      {:ok, url}
    end
  end

  defp result_url(_fleet_id, _subject, _notebook_id, _run_id, _run, _run_path), do: {:ok, nil}

  # The run's page, read whole up to `saved_page_max_bytes` and kept under its
  # address, which is the answer; nil when there is no page to keep yet.
  defp keep_page(fleet_id, subject, notebook_id, run_id, path) do
    cap = Notebooks.config()[:saved_page_max_bytes]

    with {:ok, %Req.Response{status: 200, body: page} = response} when is_binary(page) <-
           request(fleet_id, subject, :get, path, into: &read_capped(&1, &2, cap)),
         [] <- Req.Response.get_header(response, "content-encoding"),
         [^run_id] <- Req.Response.get_header(response, "x-marimohub-run-id"),
         [captured_at] <- Req.Response.get_header(response, "x-marimohub-captured-at"),
         {:ok, saved_at} <- Notebooks.saved_at(captured_at),
         {:ok, _kept} <-
           Notebooks.keep_saved_output(
             fleet_id,
             notebook_id,
             run_id,
             saved_at,
             page,
             Notebooks.run_succeeded?(response),
             actor: %System{}
           ) do
      Notebooks.result_url(fleet_id, notebook_id, run_id, saved_at)
    else
      _no_page -> nil
    end
  end

  defp read_capped({:data, data}, {request, response}, cap) do
    if byte_size(response.body) + byte_size(data) > cap,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: response.body <> data}}}
  end

  defp view(notebook_id, run, result_url) do
    %{
      notebook_id: notebook_id,
      run_id: run["run_id"],
      status: run["status"],
      result_url: result_url,
      failure: run["failure"]
    }
  end

  defp answer({:ok, %Req.Response{status: status, body: %{"data" => data}}}, status),
    do: {:ok, data}

  defp answer({:ok, %Req.Response{status: 404}}, _status), do: {:error, :not_found}
  defp answer({:ok, %Req.Response{status: 429}}, _status), do: {:error, :runs_full}
  defp answer(_response, _status), do: {:error, :unavailable}
end
