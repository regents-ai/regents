defmodule RegentsWeb.Keyfleet.Links do
  @moduledoc """
  What a Keyfleet address names, so an agent handed a link (a task's page, a
  room in a fleet's hall, the Atlas, a commit, a notebook or a saved run) reads it
  without picking the ids out by hand.

  An address is read from its own parts: a page of this site, the Atlas's
  and the workspace's links that open a notebook through it, a fleet's
  notebook host or the code host's clone address. `resolve/2` answers the
  fleet, what kind of thing the address is, its ids and the read an agent
  calls next (`read`, the WebMCP tool and the CLI command with its input),
  or `:unknown` for anything else. It never fetches the page and never says
  the thing exists: the read it names does, under that read's own rules.

  A notebook's address names the hub's space, not the project. Only a
  member reads which project holds that space (`Regents.Keyfleet.Projects`), so
  anyone else is answered the notebook with `project: nil` and no read.
  """

  alias Regents.Keyfleet.{Code, Fleets, Notebooks, Projects}

  # The names a read takes as its input; the rest describe the thing.
  @read_fields ~w(id slug project number poll_id token_id other_token_id notebook_id)a

  # A Key's number, as its pages' addresses spell it.
  @key ~r/\A[1-9][0-9]{0,17}\z/

  # The Atlas's `?kind=`, as the swarm's `source`.
  @atlas_sources %{"graph" => "graph", "notebooks" => "notebook"}

  @doc "What `url` names, as `{:ok, link}`, or `:unknown`."
  def resolve(url, actor) do
    url
    |> String.replace_prefix("siwa::", "")
    # An item's id pasted as written, `task#75`, rather than as its page's
    # address spells it, `task%2375`.
    |> String.replace(~r{/workspace/([a-z_]+)#([0-9]+)}, "/workspace/\\1%23\\2")
    |> URI.parse()
    |> case do
      %URI{scheme: "https", host: host, path: path} = uri when is_binary(host) ->
        on_host(host, path || "/", URI.decode_query(uri.query || ""), actor)

      _not_an_address ->
        :unknown
    end
  rescue
    # A part with a stray `%` doesn't decode.
    ArgumentError -> :unknown
  end

  defp on_host(host, path, query, actor) do
    cond do
      host == URI.parse(RegentsWeb.Endpoint.url()).host -> page(path, query, actor)
      host == Code.config()[:host] -> clone(path)
      match?({:ok, _fleet_id}, Notebooks.fleet_for_host(host)) -> notebook(host, path, actor)
      true -> :unknown
    end
  end

  # The Atlas and the workspace link a notebook, or a saved page of it,
  # through this site (`RegentsWeb.Keyfleet.NotebookOpenController`): `to` is its
  # path on the fleet's notebook host.
  defp page("/fleets/" <> rest, %{"to" => to}, actor) do
    with [fleet_id, "notebooks", "open"] <- String.split(rest, "/"),
         true <- Notebooks.hub?(fleet_id) do
      notebook_at(fleet_id, to, actor)
    else
      _other -> :unknown
    end
  end

  defp page(path, query, _actor) do
    case Fleets.at_path(path) do
      %{id: fleet_id, path: fleet_path} ->
        under = path |> String.replace_prefix(fleet_path, "") |> String.split("/", trim: true)
        fleet_page(fleet_id, Enum.map(under, &URI.decode/1), query)

      nil ->
        :unknown
    end
  end

  # A Key's profile opens over its fleet's page (`RegentsWeb.Keyfleet.KeyLinks.key_path/3`),
  # whatever else the address keeps beside it.
  defp fleet_page(fleet_id, [], %{"key" => token_id} = query) do
    if Regex.match?(@key, token_id),
      do: key_page(fleet_id, token_id, []),
      else: fleet_page(fleet_id, [], Map.delete(query, "key"))
  end

  defp fleet_page(fleet_id, [], %{"room" => slug}),
    do: link(fleet_id, "room", %{slug: slug}, {"rooms_messages", "rooms read"})

  defp fleet_page(fleet_id, [], _query),
    do: link(fleet_id, "fleet", %{}, {"fleets_show", "fleets get"})

  defp fleet_page(fleet_id, ["workspace"], _query),
    do: link(fleet_id, "workspace", %{}, {"workspace_board", "workspace board"})

  defp fleet_page(fleet_id, ["workspace", id], _query),
    do: link(fleet_id, "workspace_item", %{id: id}, {"workspace_show", "workspace get"})

  defp fleet_page(fleet_id, ["projects", project], _query),
    do: link(fleet_id, "project", %{project: project}, {"workspace_board", "workspace board"})

  defp fleet_page(fleet_id, ["code", repository, "commits", hash], _query) do
    with {:ok, project} <- project_of(fleet_id, repository) do
      link(
        fleet_id,
        "commit",
        code(repository, project, %{hash: hash}),
        {"code_commit", "code commit"},
        %{commit: hash}
      )
    end
  end

  # A path at a commit reads as that file, whole (`code_file` refuses one
  # that names a folder); the top folder, or the code as it stands now, is
  # the repository's to clone.
  defp fleet_page(fleet_id, ["code", repository, "files"], query) do
    with {:ok, project} <- project_of(fleet_id, repository) do
      names = code(repository, project, %{path: Map.get(query, "path", ""), at: query["at"]})

      case names do
        %{path: path, at: at} when path != "" and is_binary(at) ->
          file = %{commit: at, path: path}
          link(fleet_id, "code_files", names, {"code_file", "code file"}, file)

        _folder_or_now ->
          link(fleet_id, "code_files", names, nil)
      end
    end
  end

  defp fleet_page(fleet_id, ["proposals"], _query),
    do: link(fleet_id, "proposals", %{}, {"proposals_list", "proposals list"})

  defp fleet_page(fleet_id, ["proposals", number], _query) do
    case Integer.parse(number) do
      {number, ""} when number > 0 ->
        link(
          fleet_id,
          "proposal",
          %{number: number},
          {"proposals_show", "proposals read"},
          %{votes_after_seq: 0}
        )

      _not_a_number ->
        :unknown
    end
  end

  defp fleet_page(fleet_id, ["treasury"], _query),
    do: link(fleet_id, "treasury", %{}, {"treasury_show", "treasury get"})

  defp fleet_page(fleet_id, ["polls"], _query),
    do: link(fleet_id, "polls", %{}, {"polls_list", "polls list"})

  defp fleet_page(fleet_id, ["polls", poll_id], _query),
    do: link(fleet_id, "poll", %{poll_id: poll_id}, {"polls_show", "polls show"})

  # The Atlas reads as the swarm it draws (`RegentsWeb.Keyfleet.AtlasLive`): its
  # window, a year unless named, the day it holds and the one kind it shows.
  defp fleet_page(fleet_id, ["atlas"], query) do
    swarm =
      Map.reject(
        %{
          window: atlas_window(query["window"]),
          at: atlas_day(query["at"]),
          source: @atlas_sources[query["kind"]]
        },
        fn {_name, value} -> is_nil(value) end
      )

    link(fleet_id, "atlas", %{}, {"atlas_swarm", "atlas swarm"}, swarm)
  end

  defp fleet_page(fleet_id, ["keys", token_id | rest], _query) do
    if Regex.match?(@key, token_id), do: key_page(fleet_id, token_id, rest), else: :unknown
  end

  defp fleet_page(_fleet_id, _under, _query), do: :unknown

  defp key_page(fleet_id, token_id, []),
    do: link(fleet_id, "key", %{token_id: token_id}, {"keys_show", "keys show"})

  defp key_page(fleet_id, token_id, ["dms"]),
    do: link(fleet_id, "dms", %{token_id: token_id}, {"dms_list", "dms inbox"})

  defp key_page(fleet_id, token_id, ["dms", other]) do
    if Regex.match?(@key, other),
      do:
        link(
          fleet_id,
          "dm",
          %{token_id: token_id, other_token_id: other},
          {"dms_read", "dms read"}
        ),
      else: :unknown
  end

  defp key_page(_fleet_id, _token_id, _rest), do: :unknown

  defp atlas_window(word) when word in ~w(day week month), do: word
  defp atlas_window(_word), do: "year"

  # The start of the day the address names; now's when it names none.
  defp atlas_day(word) do
    case Date.from_iso8601(word || "") do
      {:ok, date} -> date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_iso8601()
      {:error, _not_a_day} -> nil
    end
  end

  # A project's clone address: `<fleet id>.git` for general, `<fleet
  # id>-<project>.git` for any other.
  defp clone(path) do
    with "/" <> file <- path,
         repository when repository != file <- String.replace_suffix(file, ".git", ""),
         {:ok, fleet_id} <- Code.repository_fleet(repository),
         true <- fleet_id in Fleets.catalog_ids(),
         {:ok, project} <- project_of(fleet_id, repository) do
      link(fleet_id, "repository", code(repository, project, %{}), {"code_pushes", "code pushes"})
    else
      _other -> :unknown
    end
  end

  defp project_of(fleet_id, fleet_id), do: {:ok, Projects.general()}

  defp project_of(fleet_id, repository) do
    case String.replace_prefix(repository, fleet_id <> "-", "") do
      ^repository -> :unknown
      project -> {:ok, project}
    end
  end

  defp code(repository, project, names) do
    Map.merge(names, %{
      repository: repository,
      project: project,
      clone_url: Code.agent_clone_url(repository)
    })
  end

  defp notebook(host, path, actor) do
    {:ok, fleet_id} = Notebooks.fleet_for_host(host)
    notebook_at(fleet_id, path, actor)
  end

  # A notebook, or one saved page of it, at `path` on the fleet's notebook host.
  defp notebook_at(fleet_id, path, actor) do
    if Notebooks.notebook?(path) do
      ["", "projects", space, "notebooks", notebook_id] = String.split(path, "/")
      project = space_project(fleet_id, space, actor)
      names = %{project: project, notebook_id: notebook_id}
      link(fleet_id, "notebook", names, project && {"notebooks_files", "notebooks files list"})
    else
      case Notebooks.result(path) do
        {:ok, {notebook_id, source_id, saved_at}} ->
          saved(fleet_id, notebook_id, source_id, saved_at)

        :error ->
          :unknown
      end
    end
  end

  # A saved page from a background run reads as that run; one a session
  # saved is its notebook's version, and its project isn't in the address.
  defp saved(fleet_id, notebook_id, "run_" <> _rest = run_id, saved_at) do
    names = %{project: nil, notebook_id: notebook_id, run_id: run_id, saved_at: saved_at}
    link(fleet_id, "notebook_result", names, nil)
  end

  defp saved(fleet_id, notebook_id, version, saved_at) do
    names = %{project: nil, notebook_id: notebook_id, version: version, saved_at: saved_at}
    link(fleet_id, "notebook_result", names, nil)
  end

  defp space_project(fleet_id, space, actor) do
    case Projects.projects(fleet_id, actor: actor) do
      {:ok, projects} -> Enum.find_value(projects, &(&1.hub_project_id == space && &1.name))
      {:error, _not_a_member} -> nil
    end
  end

  defp link(fleet_id, kind, names, read, extra \\ %{})

  defp link(fleet_id, kind, names, nil, _extra),
    do: {:ok, %{fleet_id: fleet_id, kind: kind, names: names, read: nil}}

  defp link(fleet_id, kind, names, {tool, command}, extra) do
    input =
      names
      |> Map.take(@read_fields)
      |> Map.merge(extra)
      |> Map.put(:fleet_id, fleet_id)

    {:ok,
     %{
       fleet_id: fleet_id,
       kind: kind,
       names: names,
       read: %{tool: tool, command: command, input: input}
     }}
  end
end
