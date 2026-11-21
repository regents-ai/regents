defmodule Regents.Keyfleet.Search do
  @moduledoc """
  A search of one fleet: the posts in its rooms and on its Keys' walls, the
  direct messages of the Keys the reader holds, and the items of its
  workspace whose words match, and the notebooks of its hub whose title or
  description holds the query, newest first, a page at a time. Each match is
  read by its own record's search, so each record's policies decide what the
  reader finds: anyone finds the posts in the rooms anyone reads and on the
  Keys' walls, a member finds every room's, only the Keys a reader may read
  and send as (`Regents.Keyfleet.Dms.Checks.KeyHolder`) bring their direct messages,
  and only those who read the workspace find its items. Posts written as a
  Key the reader muted are left out, as a room read leaves them out.

  Notebooks are asked of the fleet's hub as the reader, once it lets them in
  as on the notebook host (`Regents.Keyfleet.Notebooks.admit/3`), in the space of
  every project, so a reader finds only the notebooks the hub lists for
  them; Keyfleet keeps no copy. The hub is asked while the database is
  searched and waited on for `search_timeout_ms` at most after that. A fleet
  without a hub, a reader it doesn't let in, or a hub that doesn't answer in
  time brings no notebooks, and the rest of the search answers as usual; a
  hub that fails or doesn't answer in time is saved with the site's errors
  (`Regents.Keyfleet.Notebooks.HubSilentError`).

  Words are matched as English: "deploys" finds "deployed". A query takes
  the search box's syntax: words in quotes match as a phrase, `or` between
  words matches either, and a leading `-` leaves a word out. A notebook
  matches as the hub matches it: its title or description holds the query
  as it is written, in any case.

  ## Matches

  Every match is a map with `kind`, `id`, `at` (when it was written, when an
  item last changed, or when a notebook was added) and `match` (up to 24 of
  its words around what matched; a notebook's are of its description), and:

    * `"post"`: `seq`, `room` (`slug` and `name`, nil on a wall), `wall` (the
      Key whose wall it is on, nil in a room), `as_key` (the Key it was
      written as, nil for someone without one) and `agent` (the name of the
      agent that wrote it, or nil);
    * `"dm"`: `seq`, `key` (the reader's Key in it), `other_key`, `from_key`
      and `agent` (the agent that sent it for its person, or nil);
    * `"item"`: `type`, `title`, `project` and `archived`;
    * `"notebook"`: `title`, `project` (the project's name) and `url`, its
      address on the fleet's notebook host (`Regents.Keyfleet.Notebooks.notebook_url/3`).

  ## Pages

  Matches come newest first, then by kind, then by id, so a page's `cursor`,
  `{at, kind, id}` of its last match, is a place every kind of match is
  ordered against: passed back, the next page starts just after it. A nil
  cursor means nothing older matched.
  """

  alias Regents.Account.Actors.{Agent, Human}
  alias Regents.Keyfleet.{Access, Dms, Graph, Notebooks, Rooms}
  alias Regents.Keyfleet.Dms.Checks.KeyHolder
  alias Regents.Keyfleet.Notebooks.{HubSilentError, MemberRequest}

  @kinds ["dm", "item", "notebook", "post"]
  # The hub is asked for this many notebooks a page, the most it lists, and
  # after this many projects' at once.
  @hub_page 500
  @spaces_at_once 4
  @max_query 200
  @default_limit 20
  @max_limit 50

  @type cursor :: {DateTime.t(), String.t(), String.t()}

  @doc "The longest query a search takes, in characters."
  def max_query, do: @max_query

  @doc "The most matches a page holds, and how many it holds when not told."
  def limits, do: %{default: @default_limit, max: @max_limit}

  @doc "The kinds of match, in the order matches of one time come in."
  def kinds, do: @kinds

  @doc """
  One page of `actor`'s matches for `query` in the fleet, after `cursor` (nil
  for the newest), at most `limit` of them: `{:ok, %{matches: matches,
  cursor: cursor}}`. A query with no words in it, only words it leaves
  out, a NUL byte, or more than `max_query/0` characters answers
  `{:error, :query}`.
  """
  @spec page(String.t(), String.t(), cursor() | nil, pos_integer(), term()) ::
          {:ok, %{matches: [map()], cursor: cursor() | nil}} | {:error, :query}
  def page(fleet_id, query, cursor, limit \\ @default_limit, actor)
      when is_integer(limit) and limit in 1..@max_limit do
    query = String.trim(query)

    if String.length(query) > @max_query or String.contains?(query, <<0>>) or
         not wants_a_word?(query) do
      {:error, :query}
    else
      args = place(cursor) |> Map.put(:limit, limit)
      asked = ask_notebooks(fleet_id, query, args, actor)

      matches =
        [
          posts(fleet_id, query, args, actor),
          messages(fleet_id, query, args, actor),
          items(fleet_id, query, args, actor),
          answered(asked, fleet_id)
        ]
        |> Enum.concat()
        |> Enum.sort_by(&{-DateTime.to_unix(&1.at, :microsecond), &1.kind, &1.id})

      {page, rest} = Enum.split(matches, limit)
      {:ok, %{matches: page, cursor: next(page, rest)}}
    end
  end

  # A query must ask for at least one word: one that only leaves words out
  # matches nearly every row, and no index can find those.
  defp wants_a_word?(query) do
    ~r/-?"[^"]*"?|\S+/u
    |> Regex.scan(query)
    |> Enum.any?(fn [token] ->
      not String.starts_with?(token, "-") and String.downcase(token) != "or"
    end)
  end

  defp place(nil), do: %{}

  defp place({at, kind, id}) when kind in @kinds,
    do: %{before_at: at, before_kind: kind, before_id: id}

  defp next(_page, []), do: nil
  defp next(page, _rest), do: page |> List.last() |> then(&{&1.at, &1.kind, &1.id})

  defp posts(fleet_id, query, args, actor) do
    muted = fleet_id |> Rooms.muted_keys!(actor) |> MapSet.to_list()

    for post <-
          Rooms.search_posts!(fleet_id, query, Map.put(args, :muted, muted), actor: actor) do
      wall? = post.room.kind == :key

      %{
        kind: "post",
        id: post.id,
        at: post.inserted_at,
        match: post.match,
        seq: post.seq,
        room: if(not wall?, do: %{slug: post.room.slug, name: post.room.name}),
        wall: if(wall?, do: post.room.token_id),
        as_key: post.as_key,
        agent: name(post.agent_profile)
      }
    end
  end

  defp messages(fleet_id, query, args, actor) do
    case KeyHolder.held(actor, fleet_id) do
      [] ->
        []

      held ->
        for message <- readable(Dms.search_messages(fleet_id, held, query, args, actor: actor)) do
          mine? = message.from_token_id in held

          %{
            kind: "dm",
            id: message.id,
            at: message.inserted_at,
            match: message.match,
            seq: message.seq,
            key: if(mine?, do: message.from_token_id, else: message.to_token_id),
            other_key: if(mine?, do: message.to_token_id, else: message.from_token_id),
            from_key: message.from_token_id,
            agent: name(message.via_agent)
          }
        end
    end
  end

  defp items(fleet_id, query, args, actor) do
    if Access.allowed?(actor, :read, :workspace, fleet_id) do
      for object <- readable(Graph.search_objects(fleet_id, query, args, actor: actor)) do
        %{
          kind: "item",
          id: object.id,
          at: object.changed,
          match: object.match,
          type: object.type,
          title: object.title,
          project: object.project,
          archived: object.sys["archived"] == true
        }
      end
    else
      []
    end
  end

  # The fleet's hub is asked for its notebooks while the database is searched.
  defp ask_notebooks(fleet_id, query, args, actor) do
    if Notebooks.hub?(fleet_id),
      do: Task.async(fn -> notebooks(fleet_id, query, args, actor) end)
  end

  defp answered(nil, _fleet_id), do: []

  defp answered(asked, fleet_id) do
    wait = Notebooks.config()[:search_timeout_ms]

    case Task.yield(asked, wait) || Task.shutdown(asked, :brutal_kill) do
      {:ok, notebooks} ->
        notebooks

      nil ->
        HubSilentError.report(
          "The notebook hub of #{fleet_id} did not answer a search within #{wait} ms"
        )

        []
    end
  end

  # The notebooks after the place the hub lists for the reader, in every
  # project's space, once it lets them in.
  defp notebooks(fleet_id, query, args, actor) do
    with {:ok, subject} when is_binary(subject) <- subject(actor),
         {:ok, %{spaces: spaces}} <- Notebooks.admit(actor, fleet_id, subject) do
      spaces
      |> Task.async_stream(
        fn {project, space} -> listed(fleet_id, subject, project, space, query) end,
        max_concurrency: @spaces_at_once,
        # The search's own wait bounds every ask.
        timeout: :infinity
      )
      |> Enum.flat_map(fn {:ok, notebooks} -> notebooks end)
      |> Enum.filter(&past?(&1, args))
    else
      _not_let_in -> []
    end
  end

  defp subject(%Human{human_account_id: id} = actor) when is_integer(id),
    do: {:ok, Notebooks.subject(actor)}

  defp subject(%Agent{} = actor), do: Notebooks.agent(actor)
  defp subject(_anyone), do: {:ok, nil}

  # One project's notebooks whose title or description holds the query, as
  # the hub lists them for `subject`, each page in turn until the last. A
  # space the hub doesn't let them into brings none; a hub that fails brings
  # none and is saved with the site's errors.
  defp listed(fleet_id, subject, project, space, query, cursor \\ nil) do
    params = Enum.reject([q: query, limit: @hub_page, cursor: cursor], &is_nil(elem(&1, 1)))
    path = "/api/v1/projects/#{MemberRequest.segment(space)}/notebooks"

    case MemberRequest.request(fleet_id, subject, :get, path, params: params) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"items" => items} = page}}} ->
        found = Enum.map(items, &notebook(&1, fleet_id, project, space, query))

        case page["next_cursor"] do
          nil -> found
          next -> found ++ listed(fleet_id, subject, project, space, query, next)
        end

      {:ok, %Req.Response{status: status}} when status in [403, 404] ->
        []

      {:error, %HubSilentError{}} ->
        []

      unanswered ->
        HubSilentError.report(
          "The notebook hub of #{fleet_id} did not list #{space}'s notebooks for a search: " <>
            why(unanswered)
        )

        []
    end
  end

  defp why({:ok, %Req.Response{status: status}}), do: "it answered #{status}"
  defp why({:error, error}), do: Exception.message(error)

  defp notebook(notebook, fleet_id, project, space, query) do
    {:ok, added, _offset} = DateTime.from_iso8601(notebook["created_at"])

    %{
      kind: "notebook",
      id: notebook["id"],
      at: added,
      match: around(notebook["description"], query),
      title: notebook["title"],
      project: project,
      url: Notebooks.notebook_url(fleet_id, space, notebook["id"])
    }
  end

  # Up to 24 of the description's words, from a few before the first that
  # holds the query's first word, or its first 24 when the title matched.
  defp around(description, query) do
    words = String.split(description)
    first = query |> String.split() |> hd() |> String.downcase()
    at = Enum.find_index(words, &String.contains?(String.downcase(&1), first)) || 0
    words |> Enum.drop(max(at - 8, 0)) |> Enum.take(24) |> Enum.join(" ")
  end

  # Whether a notebook comes after the place in the order every page keeps,
  # as `Regents.Keyfleet.Preparations.SearchPage` reads the database's matches.
  defp past?(notebook, %{before_at: at, before_kind: kind, before_id: id}) do
    case DateTime.compare(notebook.at, at) do
      :lt -> true
      :eq -> {notebook.kind, notebook.id} > {kind, id}
      :gt -> false
    end
  end

  defp past?(_notebook, _newest), do: true

  # The Keys held or the workspace's readers can change between the check
  # above and the read; what the reader no longer may read is left out.
  defp readable({:ok, records}), do: records
  defp readable({:error, %Ash.Error.Forbidden{}}), do: []
  defp readable({:error, error}), do: raise(error)

  defp name(%{name: name}), do: name
  defp name(_none), do: nil
end
