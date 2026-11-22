defmodule Regents.Keyfleet.Notebooks.HubClient do
  @moduledoc """
  What this site asks of a fleet's hub, as the hub's provisioner
  (`kf_provisioner_<fleet id>`, the one super admin each hub names). Every
  call is made once: the job that makes it retries the whole job, waiting
  first while the hub does not answer (`wait_while_away/2`).

  Each answer is `{:ok, data}` or `{:error, {:hub, address, reason}}`, naming
  the hub's address and the request's error, `{:status, status}` or
  `:unexpected_page`. Adding someone already there, and removing or
  reactivating someone who isn't, answer `{:ok, nil}`.
  """

  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.Pass

  # A hub restarts on every hub deploy. A job that found it away asks again
  # this many seconds later, at most this many times.
  @away_wait 5 * 60
  @away_waits 6

  # The answers Fly's proxy gives in place of a hub that does not answer it.
  @proxy_unanswered [502, 503, 504]

  @doc "The hub user this site manages the fleet's hub as."
  def provisioner(fleet_id), do: "kf_provisioner_#{fleet_id}"

  @doc """
  What a job that asked the hub ends with, given what it got (`result`).
  While the hub gives no answer, neither its own nor through Fly's proxy
  (502, 503 or 504), the job is snoozed for #{@away_wait} seconds, which
  uses no attempt and saves no error, up to #{@away_waits} times
  (`meta["snoozed"]`), so a hub restarting for a deploy goes unremarked.
  One wait is saved all the same, where it happened: the site's own
  connections to the hub all busy (`Regents.Keyfleet.Notebooks.hub_run/2`), which
  is the site's fault rather than the hub's absence. After that, and for anything else, the job ends with `result` as it is:
  a hub that answered with a refusal fails the attempt at once, and is
  saved with the site's errors like any failed job.
  """
  def wait_while_away({:error, {:hub, _address, reason}} = error, %Oban.Job{meta: meta}) do
    if away?(reason) and Map.get(meta, "snoozed", 0) < @away_waits,
      do: {:snooze, @away_wait},
      else: error
  end

  def wait_while_away(result, %Oban.Job{}), do: result

  defp away?({:status, status}), do: status in @proxy_unanswered
  defp away?(:unexpected_page), do: false
  defp away?(_no_answer), do: true

  @doc "Every project in the hub, each with its `owner` and `tags`."
  def projects(fleet_id), do: fleet_id |> request(:get, "/api/v1/projects") |> page()

  @doc """
  The project's newest notebooks, by when each was added, as the hub lists
  them (`id`, `title`, `description`, `created_at`, ...), waiting
  `page_timeout_ms` at most, for a page that shows them. `query` is what the
  hub narrows them by: how many (`limit`), and a `tag` for only those tagged
  with it.
  """
  def notebooks(fleet_id, project_id, query) do
    fleet_id
    |> request(:get, "/api/v1/projects/#{segment(project_id)}/notebooks",
      params: query,
      receive_timeout: Notebooks.config()[:page_timeout_ms]
    )
    |> page()
  end

  @doc """
  One notebook's `meta` (`id`, `title`, `description`, `status`,
  `created_at`, ...), waiting `page_timeout_ms` at most, or nil when the hub
  has none by that id.
  """
  def notebook(fleet_id, project_id, notebook_id) do
    fleet_id
    |> request(:get, "/api/v1/projects/#{segment(project_id)}/notebooks/#{segment(notebook_id)}",
      receive_timeout: Notebooks.config()[:page_timeout_ms]
    )
    |> answer([200], [404])
    |> case do
      {:ok, %{"meta" => meta}} -> {:ok, meta}
      other -> other
    end
  end

  @doc """
  Every notebook in the project, a page of `limit` at a time, as the hub lists
  them (`id`, `title`, `author`, `updated_at`, `tags`, ...), each page read
  in turn until the last.
  """
  def all_notebooks(fleet_id, project_id, limit \\ 500),
    do: every(fleet_id, notebooks_path(project_id), limit: limit)

  @doc """
  Every notebook in the project updated after `since`, as `all_notebooks/3`
  lists them.
  """
  def notebooks_changed_after(fleet_id, project_id, %DateTime{} = since),
    do:
      every(fleet_id, notebooks_path(project_id),
        limit: 500,
        updated_after: DateTime.to_iso8601(since)
      )

  @doc """
  Every job of the notebook, as the hub lists them (`id`, `name`, ...), each
  page read in turn until the last.
  """
  def jobs(fleet_id, project_id, notebook_id),
    do: every(fleet_id, notebook_path(project_id, notebook_id) <> "/jobs", limit: 500)

  @doc """
  Every run of the job the hub still holds (it keeps them 30 days), newest
  first, each with `run_id` and `status`, each page read in turn until the
  last.
  """
  def runs(fleet_id, project_id, notebook_id, job_id),
    do:
      every(
        fleet_id,
        notebook_path(project_id, notebook_id) <> "/jobs/#{segment(job_id)}/runs",
        limit: 500
      )

  defp notebooks_path(project_id), do: "/api/v1/projects/#{segment(project_id)}/notebooks"

  defp notebook_path(project_id, notebook_id),
    do: notebooks_path(project_id) <> "/#{segment(notebook_id)}"

  defp every(fleet_id, path, query, cursor \\ nil, found \\ []) do
    params = query ++ if(cursor, do: [cursor: cursor], else: [])
    sent = request(fleet_id, :get, path, params: params)

    case answer(sent, [200]) do
      {:ok, %{"items" => items, "next_cursor" => next}} when is_binary(next) ->
        every(fleet_id, path, query, next, found ++ items)

      {:ok, %{"items" => items}} ->
        {:ok, found ++ items}

      {:ok, _other} ->
        {:error, {:hub, elem(sent, 0), :unexpected_page}}

      error ->
        error
    end
  end

  @doc """
  Makes a notebook in the project as the provisioner, titled `title` and
  tagged with `tags`, with `code`, answering its `meta`. Once the hub has
  answered, the same `idempotency_key` answers that notebook again; the hub
  records the key only after making the notebook, so one sent while the first
  is still being made can make a second.
  """
  def create_notebook(
        fleet_id,
        project_id,
        %{title: _, code: _, tags: _} = notebook,
        idempotency_key
      ) do
    fleet_id
    |> request(:post, "/api/v1/projects/#{segment(project_id)}/notebooks",
      json: Map.put(notebook, :description, ""),
      headers: [{"idempotency-key", idempotency_key}]
    )
    |> answer([201])
  end

  @doc "The notebook's code, or nil when the hub has no notebook by that id."
  def content(fleet_id, project_id, notebook_id) do
    fleet_id
    |> request(
      :get,
      "/api/v1/projects/#{segment(project_id)}/notebooks/#{segment(notebook_id)}/content"
    )
    |> answer([200], [404])
    |> case do
      {:ok, %{"code" => code}} -> {:ok, code}
      other -> other
    end
  end

  @doc "Makes a project the provisioner owns, named `name` and tagged with `tags`."
  def create_project(fleet_id, name, tags) do
    fleet_id
    |> request(:post, "/api/v1/projects", json: %{name: name, description: "", tags: tags})
    |> answer([201])
  end

  @doc """
  Deletes the project with its notebooks, as the provisioner, a manager of
  every hub project. A project already gone counts as deleted. The hub keeps
  a deleted project out of every read at once and clears it away later.
  """
  def delete_project(fleet_id, project_id) do
    fleet_id
    |> request(:delete, "/api/v1/projects/#{segment(project_id)}")
    |> answer([200], [404])
  end

  @doc "The project's members, each named by `user_id` or, when it was added by its address, `email`."
  def members(fleet_id, project_id),
    do:
      fleet_id
      |> request(:get, "/api/v1/projects/#{segment(project_id)}/members")
      |> answer([200])

  @doc "Makes `subject` an editor of the project, by the address the hub knows them by."
  def add_editor(fleet_id, project_id, subject) do
    fleet_id
    |> request(:post, "/api/v1/projects/#{segment(project_id)}/members",
      json: %{email: Notebooks.email(subject), role: "editor"}
    )
    |> answer([201], [409])
  end

  @doc "Removes a member, named by `user_id` or, for one added by its address, by `email`."
  def remove_member(fleet_id, project_id, member) do
    fleet_id
    |> request(:delete, "/api/v1/projects/#{segment(project_id)}/members/#{segment(member)}")
    |> answer([200], [404])
  end

  @doc """
  The project's sessions open now (starting, running or ending), newest
  first, each with `session_id`, `notebook_id`, `status` and `mode`.
  """
  def sessions(fleet_id, project_id),
    do:
      fleet_id
      |> request(:get, "/api/v1/projects/#{segment(project_id)}/sessions")
      |> page()

  @doc """
  Every notebook machine the hub still holds a record of: each session given
  one and each job run that started one, with `id` (the session's or the
  run's), `kind` (`session` or `run`), `started_at` and `ended_at`, null while
  it may still run.
  """
  def machines(fleet_id), do: fleet_id |> request(:get, "/api/v1/admin/machines") |> page()

  @doc "Every user who has signed in to the hub, with `suspended_at`."
  def users(fleet_id), do: fleet_id |> request(:get, "/api/v1/admin/users") |> page()

  @doc "Stops `user_id` signing in to the hub at all."
  def suspend(fleet_id, user_id) do
    fleet_id
    |> request(:put, "/api/v1/admin/users/#{segment(user_id)}/suspension")
    |> answer([200], [404])
  end

  @doc "Lets a suspended `user_id` sign in to the hub again."
  def reactivate(fleet_id, user_id) do
    fleet_id
    |> request(:delete, "/api/v1/admin/users/#{segment(user_id)}/suspension")
    |> answer([200], [404])
  end

  defp request(fleet_id, method, path, options \\ []) do
    {:ok, address} = Notebooks.hub_address(fleet_id)

    {timeout, options} =
      Keyword.pop(options, :receive_timeout, Notebooks.config()[:hub_timeout_ms])

    {address,
     Notebooks.hub_request(
       fleet_id,
       [
         method: method,
         base_url: address,
         url: path,
         headers: [{"x-keyfleet-assertion", Pass.mint(fleet_id, provisioner(fleet_id))}],
         retry: false,
         redirect: false,
         # Fly's private hub addresses are IPv6. Mint also falls back to IPv4 for local hubs.
         connect_options: [timeout: timeout, transport_opts: [inet6: true]],
         receive_timeout: timeout
       ] ++ options
     )}
  end

  defp page({address, _response} = sent) do
    case answer(sent, [200]) do
      {:ok, %{"items" => items}} -> {:ok, items}
      {:ok, _other} -> {:error, {:hub, address, :unexpected_page}}
      error -> error
    end
  end

  defp answer({address, response}, ok, settled \\ []) do
    case response do
      {:ok, %Req.Response{status: status, body: body}} ->
        cond do
          status in ok -> {:ok, data(body)}
          status in settled -> {:ok, nil}
          true -> {:error, {:hub, address, {:status, status}}}
        end

      {:error, error} ->
        {:error, {:hub, address, error}}
    end
  end

  defp data(%{"data" => data}), do: data
  defp data(_body), do: nil

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
