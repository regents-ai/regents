defmodule Regents.Keyfleet.Notebooks do
  @moduledoc """
  Each fleet's private notebook hub, opened only through this site.

  A fleet's hub answers at its own host, `<fleet id, hyphenated>.<host_suffix>`,
  and every request there reaches this site first (`RegentsWeb.Keyfleet.Plugs.NotebookGateway`).
  Whoever holds one of the fleet's keys, or an agent with an active shard of
  one, gets in; the hub knows them only by their account here:
  `u_<account id>` for a person and `a_<agent profile id>` for an agent, never
  by a wallet. Each request carries a short pass this site signs
  (`Regents.Keyfleet.Notebooks.Pass`).

  Each project of the fleet has its own space in the hub, made by a job when
  the project starts (`Regents.Keyfleet.Notebooks.Space`) and kept on the project as
  `hub_project_id`. Every member of the fleet is an editor of every space.

  A person opens the notebooks from the fleet's workspace, whose page sends
  the notebook host a code that works once (`open/4`); the notebook sign-in it sets ends
  when their Keyfleet sign-in does. When a key changes hands, a job
  brings the fleet's hub in step (`Regents.Keyfleet.Notebooks.Roster`) and ends the
  open notebook connections of whoever lost their key (`end_access/2`).
  """
  use Ash.Domain

  alias Regents.Account.Accounts.SessionAuthority
  alias Regents.Account.Actors.{Agent, Human, System}
  alias Regents.Keyfleet.AccessCache
  alias Regents.Keyfleet.Graph.Checks.KeyActor

  alias Regents.Keyfleet.Notebooks.{
    Backup,
    Files,
    Handoff,
    HubClient,
    HubSilentError,
    Makers,
    Roster
  }

  alias Regents.Keyfleet.Notebooks.{RecordsDownError, SavedOutput, Setting}
  alias Regents.Keyfleet.Projects

  resources do
    resource Regents.Keyfleet.Notebooks.Handoff

    resource Regents.Keyfleet.Notebooks.FileMaker do
      define :record_file_maker, action: :record, args: [:fleet_id, :notebook_id, :path, :maker]

      define :file_makers_at_or_under,
        action: :at_or_under,
        args: [:fleet_id, :notebook_id, :path]
    end

    resource Regents.Keyfleet.Notebooks.SavedOutput do
      define :keep_saved_output,
        action: :keep,
        args: [:fleet_id, :notebook_id, :source_id, :saved_at, :page, :succeeded]

      define :saved_output,
        action: :at,
        args: [:fleet_id, :notebook_id, :source_id, :saved_at],
        not_found_error?: false

      define :saved_outputs, action: :of_sources, args: [:fleet_id, :source_ids]

      define :last_succeeded_outputs,
        action: :last_succeeded,
        args: [:fleet_id, :notebook_ids]

      define :newest_run_outputs, action: :newest_runs, args: [:fleet_id, :notebook_ids]
      define :unmarked_run_outputs, action: :unmarked_runs, args: [:fleet_id]
      define :mark_succeeded, action: :mark_succeeded
      define :record_failure, action: :record_failure, args: [:failure]
      define :remove_saved_output, action: :remove
    end

    resource Regents.Keyfleet.Notebooks.RunSource do
      define :record_run_source,
        action: :record,
        args: [:fleet_id, :run_id, :notebook_id, :code_sha256, :files, :files_complete]

      define :run_source, action: :of_run, args: [:fleet_id, :run_id], not_found_error?: false
    end

    resource Regents.Keyfleet.Notebooks.Setting do
      define :notebook_setting,
        action: :of,
        args: [:fleet_id, :notebook_id],
        not_found_error?: false

      define :notebook_settings, action: :in_fleet, args: [:fleet_id]
    end

    resource Regents.Keyfleet.Notebooks.Backup do
      define :newest_backups, action: :newest, args: [:fleet_id]
      define :backup_copies, action: :copies, args: [:fleet_id, :project]
      define :backup, action: :read, get_by: [:id], not_found_error?: false

      define :backups_changed_before,
        action: :changed_before,
        args: [:fleet_id, :before_at, :before_id, :limit]
    end
  end

  @email_domain "identity.keyfleet.invalid"
  # How Finch begins the error it raises when no connection came free in time.
  @no_connection "Finch was unable to provide a connection"

  @doc "The notebook settings: `config :regents, :keyfleet_notebooks`."
  def config, do: Application.fetch_env!(:regents, :keyfleet_notebooks)

  @doc "The private address of the fleet's hub, as `{:ok, url}`, or `:error` when it has none."
  def hub_address(fleet_id), do: Map.fetch(config()[:fleets], fleet_id)

  @doc """
  Sends `request` to the fleet's hub, as `Req.run/2` does: `{request,
  response}`, or `{request, exception}` when the hub didn't answer. No
  connection to the hub coming free within the wait for one is reported here,
  once for every caller, and is the request's `HubSilentError`, which a
  caller that reports the hub's failures leaves as reported, and a job that
  fails with it is not saved again (`Regents.ErrorIgnorer`).
  """
  def hub_run(fleet_id, %Req.Request{} = request) do
    Req.run(request)
  rescue
    # Finch raises that wait's end, where it returns every other failure, as a
    # plain RuntimeError known only by its words (a named error is Finch issue
    # #405), and the request can run code of the caller's (`into:`), so only
    # Finch's words are caught. Match the named error once Finch has one.
    error in RuntimeError ->
      if String.starts_with?(error.message, @no_connection) do
        silent =
          HubSilentError.report(
            "No connection to the notebook hub of #{fleet_id} came free in time: " <>
              error.message
          )

        {request, silent}
      else
        reraise error, __STACKTRACE__
      end
  end

  @doc """
  Sends a request to the fleet's hub with Req's `options` (`hub_run/2`),
  answering as `Req.request/1` does: `{:ok, response}` or `{:error, exception}`.
  """
  def hub_request(fleet_id, options) do
    case hub_run(fleet_id, Req.new(options)) do
      {_request, %Req.Response{} = response} -> {:ok, response}
      {_request, exception} -> {:error, exception}
    end
  end

  @doc "Whether the fleet has a notebook hub."
  def hub?(fleet_id), do: Map.has_key?(config()[:fleets], fleet_id)

  @doc "The fleets that have a notebook hub."
  def hub_fleet_ids, do: Map.keys(config()[:fleets])

  @doc "The host the fleet's notebooks answer at."
  def host(fleet_id), do: String.replace(fleet_id, "_", "-") <> "." <> config()[:host_suffix]

  @doc "The fleet whose notebooks answer at `host`, as `{:ok, fleet_id}`, or `:error`."
  def fleet_for_host(host) do
    with [label, suffix] <- String.split(host, ".", parts: 2),
         true <- suffix == config()[:host_suffix],
         fleet_id = String.replace(label, "-", "_"),
         true <- host(fleet_id) == host and hub?(fleet_id) do
      {:ok, fleet_id}
    else
      _ -> :error
    end
  end

  @doc "Whether `host` is one of the fleets' notebook hosts, configured or not."
  def notebook_host?(host), do: String.ends_with?(host, "." <> config()[:host_suffix])

  @doc "The address of the fleet's notebooks, at `path`."
  def url(fleet_id, path, query \\ nil) do
    %URI{
      scheme: "https",
      host: host(fleet_id),
      port: config()[:public_port],
      path: path,
      query: query
    }
    |> URI.to_string()
  end

  # The hub's own id shapes (marimohub 626ec14, packages/core/src/ids.ts): a
  # saved page comes from a notebook version or from a background run. And
  # when a saved page was made, in milliseconds since 1970.
  @project_id ~r/\Aproj-[0-9a-z]{16}\z/
  @notebook_id ~r/\Anb-[0-9a-z]{16}\z/
  @source_id ~r/\A(ver_[0-9A-Z]{26}|run_[0-9A-HJKMNP-TV-Z]{26})\z/
  @saved_at ~r/\A[1-9][0-9]{0,15}\z/

  @doc """
  A saved notebook output's address: one saved page of a notebook, on the
  fleet's notebook host,
  `https://<fleet host>/results/<notebook id>/<source id>/<saved at>`. The
  source is the notebook version (`ver_…`) a session saved the page with, or
  the background run (`run_…`) that made it; `saved at` is when the hub made
  that page, in milliseconds since 1970. A hub makes a new page for a version
  each time that version's code runs again, so the time names exactly one
  page. The address shows Keyfleet's own copy of that page
  (`Regents.Keyfleet.Notebooks.SavedOutput`), whatever the hub keeps, until a member
  removes it or, for a run's page, until it is cleared 30 days after it was
  made (`Regents.Keyfleet.Notebooks.RunPagePruner`). Only the fleet's members open it,
  unless a Key made it public (`Regents.Keyfleet.Projects.Publication`): then anyone
  does, signed in or not.
  """
  def result_url(fleet_id, notebook_id, source_id, saved_at),
    do: url(fleet_id, result_path(notebook_id, source_id, saved_at))

  @doc "The path of a saved output on its fleet's notebook host."
  def result_path(notebook_id, source_id, saved_at),
    do: "/results/#{notebook_id}/#{source_id}/#{saved_at}"

  @doc """
  The saved output a path names, as `{:ok, {notebook_id, source_id, saved_at}}`,
  or `:error`. Only the address `result_path/3` spells is one.
  """
  def result(path) do
    with ["", "results", notebook_id, source_id, saved_at] <- String.split(path, "/"),
         true <-
           Regex.match?(@notebook_id, notebook_id) and Regex.match?(@source_id, source_id) and
             Regex.match?(@saved_at, saved_at) do
      {:ok, {notebook_id, source_id, String.to_integer(saved_at)}}
    else
      _ -> :error
    end
  end

  @doc """
  When a hub made a saved page, from its `X-Marimohub-Captured-At` time, as
  `{:ok, milliseconds since 1970}`, or `:error`.
  """
  def saved_at(captured_at) do
    case DateTime.from_iso8601(captured_at) do
      {:ok, at, _offset} -> {:ok, DateTime.to_unix(at, :millisecond)}
      {:error, _reason} -> :error
    end
  end

  @doc """
  Whether a hub's saved page is a background run's that succeeded, from the
  run's status in its `X-Marimohub-Run-Status`. A version's page names none.
  """
  def run_succeeded?(%Req.Response{} = response),
    do: Req.Response.get_header(response, "x-marimohub-run-status") == ["succeeded"]

  @doc """
  Whether a notebook was changed after `page`, a kept page of it, was made,
  from `updated_at`, when the hub last changed the notebook (ISO 8601): the
  hub moves a notebook's `updated_at` when its code, packages or details
  change.
  """
  def changed_since?(updated_at, %SavedOutput{saved_at: saved_at}) do
    {:ok, at, _offset} = DateTime.from_iso8601(updated_at)
    DateTime.to_unix(at, :millisecond) > saved_at
  end

  @doc """
  Records how background run `run_id` failed, `failure` as the hub's record
  of the run names it, on the fleet's copies of the run's page that record
  none yet and are not marked succeeded (`Regents.Keyfleet.Notebooks.SavedOutput`):
  where it stopped and the hub's sentence for it, `stage` and `message`, never
  the output excerpt, which the hub shows only to whoever started the run and
  the notebook's author. A failure once recorded stays. Nil records nothing.
  A copy that can't be marked is saved with the site's errors; the answer is
  `:ok` either way.
  """
  def record_run_failure(_fleet_id, _run_id, nil), do: :ok

  def record_run_failure(fleet_id, run_id, failure) do
    SavedOutput
    |> Ash.Query.for_read(:of_sources, %{fleet_id: fleet_id, source_ids: [run_id]},
      actor: %System{}
    )
    |> record_failure(Map.take(failure, ["stage", "message"]),
      actor: %System{},
      bulk_options: [strategy: :atomic, notify?: false, return_errors?: true]
    )
    |> case do
      %Ash.BulkResult{status: :success} ->
        :ok

      %Ash.BulkResult{errors: errors} ->
        RecordsDownError.report(
          "How #{fleet_id}'s run #{run_id} failed could not be kept: " <>
            inspect(Enum.map(errors, & &1.__struct__))
        )

        :ok
    end
  end

  @doc "The path of one notebook on its fleet's notebook host, where it opens to edit."
  def notebook_path(project_id, notebook_id),
    do: "/projects/#{project_id}/notebooks/#{notebook_id}"

  @doc """
  The address of one notebook on its fleet's notebook host, as a task cites
  it in `notebook_ref`.
  """
  def notebook_url(fleet_id, project_id, notebook_id),
    do: url(fleet_id, notebook_path(project_id, notebook_id))

  @doc """
  Where a link that opens the notebooks may land: their start page, one
  notebook (`notebook_path/2`) or a saved output.
  """
  def destination?("/"), do: true

  def destination?(path) when is_binary(path),
    do: notebook?(path) or result(path) != :error

  def destination?(_path), do: false

  @doc "Whether `path` is one notebook's path on its fleet's notebook host (`notebook_path/2`)."
  def notebook?(path) do
    case String.split(path, "/") do
      ["", "projects", project_id, "notebooks", notebook_id] ->
        Regex.match?(@project_id, project_id) and Regex.match?(@notebook_id, notebook_id)

      _other ->
        false
    end
  end

  @doc "Whether `id` is shaped as a hub's notebook ids are."
  def notebook_id?(id), do: Regex.match?(@notebook_id, id)

  @doc "How the hubs know a person: by their account here."
  def subject(%Human{human_account_id: id}) when is_integer(id), do: "u_#{id}"

  @doc "How the hubs know an agent: by its profile here."
  def agent_subject(profile_id), do: "a_#{profile_id}"

  @doc "The address a hub keeps for `subject`. It receives no mail."
  def email(subject), do: subject <> "@" <> @email_domain

  @doc "The subject an address the hubs keep stands for, or nil when it is none of ours."
  def subject_of_email(email) do
    case String.split(email, "@") do
      [subject, @email_domain] -> if managed_subject?(subject), do: subject
      _other -> nil
    end
  end

  @doc "Whether this site manages the hub user `subject`: a person's or an agent's."
  def managed_subject?("u_" <> id), do: id != ""
  def managed_subject?("a_" <> id), do: id != ""
  def managed_subject?(_subject), do: false

  @doc """
  Whether `actor` may open the fleet's notebooks now: `{:ok, true}` when it
  holds one of the fleet's keys or, for an agent, an active shard of one,
  `{:ok, false}` when it holds neither, and `{:error, error}` when the fleet's
  key ownership can't be read right now.

  The answer is the workspace's own (`KeyActor.member/3`): who may read the
  workspace may open its notebooks.
  """
  def member?(actor, fleet_id) do
    KeyActor.member(
      actor,
      fleet_id,
      Application.fetch_env!(:regents, :keyfleet_graph)[:check_timeout]
    )
  end

  @doc """
  Whether `actor` is one of the fleet's members now (`member?/2`), and
  whether a vote of the fleet has restricted the edits of the Key it is in
  the fleet as: `{:ok, %{restricted?: boolean}}`, `{:ok, nil}` when it is
  not a member, or `{:error, error}` when either can't be read right now. A
  restricted Key opens and reads the notebooks but changes nothing in them.
  """
  def membership(actor, fleet_id) do
    within = Application.fetch_env!(:regents, :keyfleet_graph)[:check_timeout]

    with {:ok, %{} = member} <- KeyActor.membership(actor, fleet_id, within),
         do: {:ok, Map.take(member, [:restricted?])}
  end

  @doc """
  Lets `actor`, known to the hubs as `subject`, into the fleet's notebooks
  now: `{:ok, %{spaces:, restricted?:}}` once it is one of the fleet's
  members (`membership/2`, which says whether its Key's edits are
  restricted) and an editor of every space the fleet's projects have in the
  hub (`spaces`, each project's name with its space), or
  `{:error, reason}`: `:not_holder`, `:catching_up` while key ownership can't
  be read, `:setting_up` while the hub has no space yet (a job is booked
  to make them), or `:unavailable` when the hub didn't answer. Someone who lost
  a key and holds one again was suspended in the hub, and is let back in.
  """
  def admit(actor, fleet_id, subject) do
    with {:holder, {:ok, %{restricted?: restricted?}}} <-
           {:holder, membership(actor, fleet_id)},
         {:spaces, {:ok, [_ | _] = spaces}} <- {:spaces, spaces(fleet_id)},
         {:hub, :ok} <- {:hub, make_editor(fleet_id, spaces, subject)} do
      access = %{spaces: Map.new(spaces), restricted?: restricted?}
      AccessCache.admit(:notebooks, fleet_id, subject, access, config()[:access_ttl_ms])
      {:ok, access}
    else
      {:holder, {:ok, nil}} ->
        {:error, :not_holder}

      {:holder, {:error, _error}} ->
        {:error, :catching_up}

      {:spaces, {:ok, []}} ->
        Oban.insert!(Roster.new(%{fleet_id: fleet_id}))
        {:error, :setting_up}

      {:spaces, {:error, _error}} ->
        {:error, :unavailable}

      {:hub, {:error, {:hub, _address, %HubSilentError{}}}} ->
        {:error, :unavailable}

      {:hub, {:error, reason}} ->
        HubSilentError.report(
          "The notebook hub of #{fleet_id} did not make a holder an editor: #{inspect(reason)}"
        )

        {:error, :unavailable}
    end
  end

  # Once made an editor of every space the fleet has, `subject` is not asked
  # of the hub again for `editor_ttl_ms`, or until its access ends or the
  # fleet gains a space; the ten-minute roster run keeps the hub in step
  # meanwhile.
  defp make_editor(fleet_id, spaces, subject) do
    case AccessCache.lookup(:hub_editor, fleet_id, subject) do
      {:ok, ^spaces} ->
        :ok

      _stale ->
        with {:ok, _added} <- each_space(spaces, &HubClient.add_editor(fleet_id, &1, subject)),
             {:ok, _reactivated} <- HubClient.reactivate(fleet_id, subject) do
          AccessCache.admit(:hub_editor, fleet_id, subject, spaces, config()[:editor_ttl_ms])
        end
    end
  end

  # Asks the hub `ask` of each space in turn, as `{:ok, answers}`, stopping
  # at the first that fails.
  defp each_space(spaces, ask) do
    Enum.reduce_while(spaces, {:ok, []}, fn {_project, space}, {:ok, answers} ->
      case ask.(space) do
        {:ok, answer} -> {:cont, {:ok, [answer | answers]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Whether the fleet's notebooks have room for a session of `notebook_id` now,
  whoever starts it: `{:ok, true}` while fewer than `max_sessions` are open
  across all of the fleet's spaces, or when one of them is already that
  notebook's, which starting it again joins; `{:ok, false}` when they are
  full; or `{:error, :unavailable}` when the open sessions can't be read. A
  background run is the hub's job, not a session, so it takes no room. Two
  sessions started at the same moment may both find the last place.
  """
  def session_room?(fleet_id, notebook_id) do
    with {:spaces, {:ok, spaces}} <- {:spaces, spaces(fleet_id)},
         {:hub, {:ok, open}} <- {:hub, each_space(spaces, &HubClient.sessions(fleet_id, &1))} do
      sessions = Enum.concat(open)

      {:ok,
       length(sessions) < config()[:max_sessions] or
         Enum.any?(sessions, &(&1["notebook_id"] == notebook_id))}
    else
      {:spaces, {:error, _error}} ->
        {:error, :unavailable}

      {:hub, {:error, {:hub, _address, %HubSilentError{}}}} ->
        {:error, :unavailable}

      {:hub, {:error, reason}} ->
        HubSilentError.report(
          "The notebook hub of #{fleet_id} did not list its open sessions: #{inspect(reason)}"
        )

        {:error, :unavailable}
    end
  end

  @doc """
  Opens the fleet's notebooks for a person signed in by the session `lineage`:
  `{:ok, %{action: url, code: code, to: to}}`, the form Keyfleet's page sends
  to the fleet's notebook address, with a code that works once, for
  `handoff_ttl_seconds`, landing on `to` (`destination?/1`: the start page,
  one notebook or a saved output); `{:error, :no_hub}` when the fleet has no notebooks;
  `{:error, :invalid_destination}` for anywhere else to land;
  `{:error, :signed_out}` when that sign-in is no longer current;
  `{:error, :not_holder}` when they hold none of the fleet's keys; or `{:error, error}`
  when ownership can't be read right now.
  """
  def open(%Human{human_account_id: account_id} = actor, lineage, fleet_id, to \\ "/") do
    with true <- hub?(fleet_id) || {:error, :no_hub},
         true <- destination?(to) || {:error, :invalid_destination},
         session_id when is_binary(session_id) <-
           SessionAuthority.current_id(lineage, account_id) || {:error, :signed_out},
         {:ok, true} <- member?(actor, fleet_id) do
      code = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      expires_at = DateTime.add(DateTime.utc_now(), config()[:handoff_ttl_seconds], :second)

      Handoff
      |> Ash.Changeset.for_create(
        :issue,
        %{
          code_hash: hash(code),
          fleet_id: fleet_id,
          human_account_id: account_id,
          session_authority_id: session_id,
          expires_at: expires_at
        },
        actor: %System{}
      )
      |> Ash.create!()

      {:ok, %{action: url(fleet_id, "/_keyfleet/enter"), code: code, to: to}}
    else
      {:ok, false} -> {:error, :not_holder}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Spends a code `open/4` made for the fleet: `{:ok, {human_account_id,
  session_authority_id}}` the first time, within its time, and `:error` after that, for another fleet, or
  for a code it never made. One statement checks and spends it, so two
  requests with the same code can't both get in.
  """
  def redeem(fleet_id, code) when is_binary(code) do
    Handoff
    |> Ash.Query.for_read(:redeemable, %{code_hash: hash(code), fleet_id: fleet_id},
      actor: %System{}
    )
    |> Ash.bulk_update!(:redeem, %{},
      actor: %System{},
      strategy: :atomic,
      return_records?: true,
      notify?: false
    )
    |> case do
      %Ash.BulkResult{records: [%Handoff{} = handoff]} ->
        {:ok, {handoff.human_account_id, handoff.session_authority_id}}

      %Ash.BulkResult{records: []} ->
        :error
    end
  end

  def redeem(_fleet_id, _code), do: :error

  defp hash(code), do: :crypto.hash(:sha256, code)

  @doc """
  The person a notebook sign-in names, while the Keyfleet sign-in it was opened
  under is still current: `{:ok, actor, topic, ends_at}`, where `topic` is
  where that sign-in's ending is announced and `ends_at` is when it runs out,
  or `:signed_out` once they signed out there, switched account or it ran out.
  """
  def person(session_authority_id, account_id) do
    case SessionAuthority.signed_in(session_authority_id, account_id) do
      nil -> :signed_out
      {account, topic, ends_at} -> {:ok, Human.for_account(account), topic, ends_at}
    end
  end

  @doc "The agent a signed request names, with the subject the hubs know it by, or nil without a profile."
  def agent(%Agent{} = actor) do
    case Regents.Keyfleet.Agents.get_my_profile(actor: actor) do
      {:ok, nil} -> {:ok, nil}
      {:ok, profile} -> {:ok, agent_subject(profile.id)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Ends everyone's admission to the fleet's notebooks on every node now, so
  each one's next request is checked afresh (from `Regents.Keyfleet.Chain.Scanner`,
  when the fleet's Keys change).
  """
  def end_access(fleet_id) do
    AccessCache.end_fleet(:notebooks, fleet_id)
    AccessCache.end_fleet(:hub_editor, fleet_id)
  end

  @doc """
  Ends `subject`'s access to the fleet's notebooks on every node now: its open
  notebook connections close and its next request is checked afresh.
  """
  def end_access(fleet_id, subject) do
    AccessCache.end_access(:notebooks, fleet_id, subject)
    AccessCache.end_access(:hub_editor, fleet_id, subject)

    Phoenix.PubSub.broadcast(
      Regents.PubSub,
      access_topic(fleet_id, subject),
      :notebook_access_ended
    )
  end

  @doc """
  Where one subject's open notebook connections to a fleet are registered:
  each connection subscribes here, and `end_access/2` closes them all.
  """
  def access_topic(fleet_id, subject), do: "keyfleet:notebook_access:#{fleet_id}:#{subject}"

  @doc """
  The spaces the fleet's projects have in its hub so far, oldest project
  first, as `{:ok, [{project name, space}]}`. A project's space is made by a
  job once it starts (`Regents.Keyfleet.Notebooks.Space`).
  """
  def spaces(fleet_id) do
    with {:ok, projects} <- Projects.projects(fleet_id, actor: %System{}) do
      {:ok, for(%{hub_project_id: space} = project <- projects, space, do: {project.name, space})}
    end
  end

  @doc """
  Whether `space` in the fleet's hub is an archived project's, where nobody
  changes anything until a Key takes the project over: `{:ok, boolean}`, or
  `{:error, error}` when the projects can't be read.
  """
  def archived_space?(fleet_id, space) do
    with {:ok, projects} <- Projects.projects(fleet_id, actor: %System{}),
         do: {:ok, Enum.any?(projects, &(&1.hub_project_id == space and &1.state == :archived))}
  end

  @doc "The project's space in its fleet's hub, as `{:ok, space}`, or `{:ok, nil}` before it is made."
  def space(fleet_id, project) do
    with {:ok, found} <- Projects.project(fleet_id, project, actor: %System{}),
         do: {:ok, found && found.hub_project_id}
  end

  ## Locks

  @doc """
  Locks (`locked?` true) or unlocks a notebook of the fleet's active project
  `project`, as `actor`, known to the hub as `subject`. Only the notebook's
  creator does (`Regents.Keyfleet.Notebooks.Makers`): its author in the hub, or for a
  Key's scratchpad whoever acts as that Key. Answers `{:ok, %{notebook_id:,
  locked:}}`, or `{:error, reason}`: a `Regents.Keyfleet.Projects.Errors.ClosedError`
  for an archived or unknown project, `:setting_up` before the project's
  space is made, `:not_holder`, `:edits_restricted`, `:not_maker`,
  `:not_found` for a notebook the project doesn't have, or `:unavailable`.
  """
  def lock(fleet_id, actor, subject, project, notebook_id, locked?) do
    with {:ok, space} <- open_space(fleet_id, project),
         :ok <- unrestricted(actor, fleet_id),
         :ok <- creator(fleet_id, actor, subject, space, notebook_id) do
      Regents.Repo.transaction(fn ->
        switch(actor, fleet_id, notebook_id, locked?)
      end)
    end
  end

  # Saved with an agent's pairing held until it commits and the Key's edits
  # read again in the same transaction.
  defp switch(actor, fleet_id, notebook_id, locked?) do
    with :ok <- held(actor),
         :ok <- unrestricted(actor, fleet_id) do
      Setting
      |> Ash.Changeset.for_create(
        :switch,
        %{fleet_id: fleet_id, notebook_id: notebook_id, unlocked: not locked?},
        actor: %System{}
      )
      |> Ash.create!()

      %{notebook_id: notebook_id, locked: locked?}
    else
      {:error, reason} -> Regents.Repo.rollback(reason)
    end
  end

  defp held(actor) do
    with {:error, _not_paired} <- KeyActor.hold_pairing(actor), do: {:error, :not_holder}
  end

  defp creator(fleet_id, actor, subject, space, notebook_id) do
    case Makers.open_to?(fleet_id, actor, notebook_id, :creator) do
      {:ok, true} -> :ok
      {:ok, false} -> Makers.notebook(fleet_id, subject, space, notebook_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  What Keyfleet keeps of each of these notebooks of the fleet, by id: whether
  it is locked, and the Key whose scratchpad it is, if any. A notebook with
  nothing kept is locked and nobody's scratchpad.
  """
  def locks(fleet_id) do
    for setting <- notebook_settings!(fleet_id, actor: %System{}),
        into: %{},
        do: {setting.notebook_id, %{locked: not setting.unlocked, key: setting.key}}
  end

  @doc """
  The Key each notebook's maker writes as in the fleet, by notebook id: the
  Key whose scratchpad it is, else its author's, a person's or an agent's
  (`Regents.Keyfleet.Keys.identity/2`); nil for a notebook this site didn't make for
  someone, or whose maker holds no Key now. Each notebook is a map with its
  `id` and `author` as the hub lists them.
  """
  def keys(fleet_id, notebooks) do
    locks = locks(fleet_id)
    authors = notebooks |> Enum.map(& &1.author) |> Enum.uniq()

    people =
      for "u_" <> id <- authors, {account, ""} <- [Integer.parse(id)], do: account

    agents =
      for "a_" <> id <- authors, {:ok, profile} <- [Ecto.UUID.cast(id)], do: profile

    people_keys =
      for account <- Regents.Account.Accounts.accounts_by_ids!(people, actor: %System{}),
          key = Regents.Keyfleet.Keys.identity(Human.for_account(account), fleet_id),
          into: %{},
          do: {subject(%Human{human_account_id: account.id}), key.token_id}

    agent_keys =
      for profile <-
            Regents.Keyfleet.Agents.listings!(agents,
              load: [key: %{fleet_id: fleet_id}],
              actor: %System{}
            ),
          profile.key,
          into: %{},
          do: {agent_subject(profile.id), profile.key}

    by_author = Map.merge(people_keys, agent_keys)

    Map.new(notebooks, fn notebook ->
      {notebook.id, get_in(locks, [notebook.id, :key]) || by_author[notebook.author]}
    end)
  end

  @doc """
  Forgets what Keyfleet keeps of a notebook once its hub deleted it. When
  that can't be done now it is reported, and the next scratchpad run
  forgets a deleted scratchpad (`Regents.Keyfleet.Notebooks.Scratchpads`).
  """
  def forget_notebook(fleet_id, notebook_id) do
    with {:ok, setting} when not is_nil(setting) <-
           notebook_setting(fleet_id, notebook_id, actor: %System{}),
         {:error, error} <- Ash.destroy(setting, action: :forget, actor: %System{}) do
      Makers.down("forgotten", fleet_id, notebook_id, error)
    else
      {:ok, nil} -> :ok
      :ok -> :ok
      {:error, error} -> Makers.down("read", fleet_id, notebook_id, error)
    end
  end

  ## Daily copies

  @doc """
  The daily copies of the notebooks of the fleet's project `project`
  (`Regents.Keyfleet.Notebooks.Backup`), for one of its members, `actor`, known to
  the hub as `subject`: each notebook once, newest copy first, with its
  copies, newest first, and whether `actor` may bring each back
  (`restorable`). `{:error, :not_holder}` for anyone else, or
  `{:error, :unavailable}` when membership can't be read now.
  """
  def copies(fleet_id, actor, subject, project) do
    case KeyActor.membership(actor, fleet_id, check_timeout()) do
      {:ok, %{token_id: key}} ->
        {:ok, kept_copies(fleet_id, subject, project, key)}

      {:ok, nil} ->
        {:error, :not_holder}

      {:error, _error} ->
        {:error, :unavailable}
    end
  end

  defp kept_copies(fleet_id, subject, project, key) do
    fleet_id
    |> backup_copies!(project, actor: %System{})
    |> Enum.group_by(& &1.notebook_id)
    |> Enum.map(fn {notebook_id, [newest | _] = copies} ->
      %{
        notebook_id: notebook_id,
        title: newest.title,
        copies:
          for copy <- copies do
            %{
              id: copy.id,
              changed_at: copy.changed_at,
              restorable: copy.unlocked or copy.author == subject or copy.key == key
            }
          end
      }
    end)
    |> Enum.sort_by(&hd(&1.copies).changed_at, {:desc, DateTime})
  end

  @doc """
  Brings a daily copy of a notebook of the fleet's project `project` back as
  a new notebook there, made by `subject` as `actor`, titled after the
  notebook and the day it was copied.
  Anyone who could edit the notebook when it was copied may: its creator, any
  member while it was unlocked, or whoever acts as the Key whose scratchpad
  it was. Answers `{:ok, %{notebook_id:, title:, notebook_url:}}`, or
  `{:error, reason}`: `:copy_not_found`, as `lock/6` for its project and
  standing, `:not_maker` for anyone else, or as
  `Regents.Keyfleet.Notebooks.Files.create/5` for the hub's answer.
  """
  def restore(fleet_id, actor, subject, project, backup_id) do
    with {:copy, {:ok, %Backup{fleet_id: ^fleet_id, project: ^project} = copy}} <-
           {:copy, backup(backup_id, actor: %System{})},
         {:ok, space} <- open_space(fleet_id, project),
         :ok <- unrestricted(actor, fleet_id),
         :ok <- could_edit(copy, actor, subject) do
      title = "#{copy.title} (copy of #{Calendar.strftime(copy.changed_at, "%-d %b %Y")})"

      Files.create(
        fleet_id,
        subject,
        space,
        %{"title" => title, "code" => copy.code},
        "restore:#{copy.id}:#{subject}"
      )
    else
      {:copy, _none} -> {:error, :copy_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp could_edit(%Backup{unlocked: true}, _actor, _subject), do: :ok
  defp could_edit(%Backup{author: subject}, _actor, subject), do: :ok
  defp could_edit(%Backup{key: nil}, _actor, _subject), do: {:error, :not_maker}

  defp could_edit(%Backup{fleet_id: fleet_id, key: key}, actor, _subject) do
    case Makers.acts_as(actor, fleet_id, key) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :not_maker}
      {:error, reason} -> {:error, reason}
    end
  end

  # The space of the fleet's project `project` while it takes changes.
  defp open_space(fleet_id, project) do
    with {:ok, %{hub_project_id: space}} <- Projects.open(fleet_id, project),
         do: if(space, do: {:ok, space}, else: {:error, :setting_up})
  end

  defp unrestricted(actor, fleet_id) do
    case membership(actor, fleet_id) do
      {:ok, %{restricted?: false}} -> :ok
      {:ok, %{restricted?: true}} -> {:error, :edits_restricted}
      {:ok, nil} -> {:error, :not_holder}
      {:error, _error} -> {:error, :unavailable}
    end
  end

  defp check_timeout, do: Application.fetch_env!(:regents, :keyfleet_graph)[:check_timeout]
end
