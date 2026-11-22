defmodule RegentsWeb.Keyfleet.WorkspacePage do
  @moduledoc """
  What a fleet's workspace pages show, read from the workspace's read tables
  alone, never from the fleet's writer.

  `board/3` is one of the workspace's four places (`places/0`), in one of
  the fleet's projects (`Regents.Keyfleet.Projects`) or across all of them. Its
  Project is the items a page at a time, the most recently changed first,
  beside the goals and the latest changes; its Docs the newest notebooks;
  its Code the project's repository, its top folder and the changes sent to
  it (`Regents.Keyfleet.Code`), or every project's repository in turn. Docs and Code
  each list what the fleet's members pinned there (`Regents.Keyfleet.Graph.Pin`).
  Public is what the fleet's Keys made public
  (`Regents.Keyfleet.Projects.Publication`), newest first, and anyone reads it.
  `item/4` is one item with its fields, its links a page at a time and its
  history a page at a time, and a goal with the work around it in place of
  its links. Goals are listed one line each,
  the board's and every list of goals. Each answers
  `seen`, the log and the place in it the read tables had reached when the
  page was read. Every change is told as one plain line: a list of parts, each a piece of text, a key
  (`{:key, token_id, agent}`, with the name of the agent that wrote as it, or
  nil) or an item (`{:item, id, title}`, with a `nil` title when the item is
  not in the workspace). Who added an item is a key told the same way, so two
  agents writing as one person's key are told apart; a starting goal, one of
  the ideas every workspace begins with (`Regents.Keyfleet.GoalIdeas`), was added by
  Keyfleet.

  `commit/4` is one commit in one of the fleet's repositories, at the
  address a workspace cites it by (`commit_url/3`): who sent it, and the evidence that cites it
  with the tasks that produced that evidence.

  Only the fleet's members read its workspace
  (`Regents.Keyfleet.Graph.Checks.KeyReader`) and its code: for anyone else every page
  answers `members_only?: true`, with what the fleet shows anyone of its
  workspace: each project by title with the titles of its open goals
  (`RegentsWeb.Keyfleet.FleetPage.read_recent_work/1`), and nothing else members
  write, except the Public place, which reads the same for everyone.

  A page name that is not one the tables can answer, such as an unknown type
  or a damaged page position, is a page that doesn't exist.
  """

  require Logger

  alias Regents.Account.Actors.{Human, System}
  alias Regents.Keyfleet.{Agents, Code, Fleets, Keys, Notebooks, Projects}
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Graph.RerunCheck
  alias Regents.Keyfleet.Notebooks.HubClient
  alias Regents.Keyfleet.Projects.Publish
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Message
  alias RegentsWeb.Endpoint
  alias RegentsWeb.Keyfleet.ActivityLines
  alias RegentsWeb.Keyfleet.DirectoryMD
  alias RegentsWeb.Keyfleet.FleetPage
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.RoomsLive
  alias RegentsWeb.Keyfleet.WorkspaceGraph
  alias RegentsWeb.NotFoundError

  @types ~w(goal task finding evidence service note dead_end review)

  @type_names %{
    "goal" => {"goal", "Goals"},
    "task" => {"task", "Tasks"},
    "finding" => {"finding", "Findings"},
    "evidence" => {"evidence", "Evidence"},
    "service" => {"service", "Services"},
    "note" => {"note", "Notes"},
    "dead_end" => {"dead end", "Dead ends"},
    "review" => {"review", "Reviews"}
  }

  # Each type's fields in the order they are shown, with their names; any
  # other field is shown after them under its own name.
  @fields %{
    "goal" => [
      {"outcome", "Outcome"},
      {"status", "Status"},
      {"success_criteria", "Success criteria"},
      {"open_questions", "Open questions"}
    ],
    "task" => [
      {"progress", "Progress"},
      {"deliverable", "Deliverable"},
      {"acceptance_criteria", "Done when"},
      {"next_step", "Next step"},
      {"notebook_ref", "Notebook"},
      {"commit_ref", "Commit"},
      {"rerun", "Rerun"},
      {"result_ref", "Result"}
    ],
    "finding" => [
      {"statement", "Statement"},
      {"confidence", "Confidence"},
      {"uncertainty", "Uncertainty"}
    ],
    "evidence" => [
      {"source_uri", "Source"},
      {"excerpt", "Excerpt"},
      {"how_obtained", "Method"},
      {"digest", "Document code"}
    ],
    "service" => [
      {"customer", "Customer"},
      {"problem", "Problem"},
      {"deliverable", "Deliverable"},
      {"price_proposal", "Proposed price"},
      {"payment_asset", "Paid in"},
      {"implementation_refs", "Work"}
    ],
    "note" => [{"body", "Note"}],
    "dead_end" => [
      {"what_was_tried", "Approach tried"},
      {"why_it_failed", "Reason"}
    ],
    "review" => [
      {"decision", "Decision"},
      {"reproduction", "Reproduced"},
      {"rationale", "Reasons"},
      {"conflicts_of_interest", "Conflicts"}
    ]
  }

  @choices %{
    "progress" => %{
      "todo" => "To do",
      "doing" => "In progress",
      "blocked" => "Blocked",
      "done" => "Submitted"
    },
    "review" => %{
      "awaiting_review" => "Awaiting review",
      "accepted" => "Accepted",
      "reproduced" => "Reproduced",
      "disputed" => "Disputed"
    },
    "decision" => %{"accept" => "Accepted", "dispute" => "Disputed"},
    "reproduction" => %{"passed" => "Yes", "failed" => "No"},
    "status" => %{"open" => "Open", "achieved" => "Achieved", "dropped" => "Dropped"},
    "confidence" => %{"low" => "Low", "medium" => "Medium", "high" => "High"},
    "payment_asset" => %{
      "USDC" => "USDC",
      "REGENT" => "REGENT",
      "FLEET_TOKEN" => "the fleet’s own token"
    }
  }

  # What one item is to another, read from the link's source to its target.
  @relations %{
    "supports" => "supports",
    "contradicts" => "contradicts",
    "depends_on" => "depends on",
    "implements" => "delivers on",
    "produces" => "produces",
    "references" => "mentions",
    "reviews" => "reviews",
    "forks" => "copies"
  }

  # How many goals the board lists above the fleet's other work.
  @board_goals 12

  # The workspace's places, as the address names each: the Project when it
  # names none.
  @places %{nil => :project, "docs" => :docs, "code" => :code, "public" => :public}

  # How many things made public the Public place lists, newest first.
  @public_shown 12

  # How many notebooks the Docs place lists, newest first: one project's, or
  # each project's in the whole fleet's view.
  @docs_shown 24
  @section_shown 6
  # How many notebooks the Docs place's canvas draws, the most recently
  # changed, as many as the Graph view draws items.
  @canvas_notebooks 120

  # How a tree canvas arranges its cards, as the address names each: by when
  # each was made when it names none, by the Key that made it, or by how
  # recently it changed. Made times are sliced by the day, or by the hour.
  @arranges %{"author" => :author, "activity" => :activity}

  # How many goals the Graph view steps through.
  @step_goals 120
  # How many lines each small panel under the Graph view's stage shows.
  @instrument_rows 6
  # How many items of the work around a goal, the most recently changed, its
  # page reads for what they cite.
  @goal_items 100
  # How many of the notebooks its work cites a goal's page asks the hub for.
  @cited_notebooks 20
  # The fields by which a goal's tasks and evidence cite their results,
  # notebooks and commits.
  @cites ["source_uri", "result_ref", "notebook_ref", "commit_ref"]

  # Only these kinds of address are ever made into links.
  @link_schemes ["https://", "ipfs://", "ar://", "git+https://"]
  @room_slug ~r/\A[a-z0-9][a-z0-9-]{0,62}\z/
  # One saved page of a notebook version or background run, after the
  # notebooks' `/results/`: notebook id, version or run id, and when the page
  # was saved in milliseconds since 1970.
  # A page of history, and the most pages back a reader goes: past that, git
  # itself reads further.
  @history_page 30
  @history_pages 300

  @saved_result ~r/\Anb-[a-z0-9]{16}\/(ver_[0-9A-Z]{26}|run_[0-9A-HJKMNP-TV-Z]{26})\/[1-9][0-9]{0,15}\z/

  @doc "The types of item a workspace holds."
  def types, do: @types

  @doc "The name of a type, and of several of it."
  def type_name(type), do: Map.get(@type_names, type, {"item", "Items"})

  @doc "The path of an item's page."
  def item_path(fleet_id, id, query \\ []),
    do:
      with_query(
        "#{Regents.Keyfleet.Fleets.path(fleet_id)}/workspace/#{URI.encode(id, &URI.char_unreserved?/1)}",
        query
      )

  @doc """
  The path of the fleet's workspace, showing `filter` from `position`: on the
  board, or in the graph (`view: :graph`), where `owner` names the Key whose
  items it draws, arranged as `arrange` and `every` say.
  """
  def board_path(fleet_id, filter, position \\ []) do
    graph? = filter.view == :graph

    with_query(
      "#{Regents.Keyfleet.Fleets.path(fleet_id)}/workspace",
      given(
        [
          view: if(graph?, do: "graph"),
          project: filter.project,
          type: filter.type,
          owner: filter.owner,
          goal: filter.goal,
          archived: if(filter.archived?, do: "shown")
        ] ++ if(graph?, do: arrangement(filter), else: []) ++ position
      )
    )
  end

  @doc "The workspace's places, in the order a page offers them."
  def places, do: [:project, :docs, :code, :public]

  @doc "The path of one of the workspace's places, in one project or, for nil, all of them."
  def place_path(fleet_id, place, project \\ nil) do
    with_query(
      "#{Regents.Keyfleet.Fleets.path(fleet_id)}/workspace",
      given(place: if(place != :project, do: place), project: project)
    )
  end

  @doc """
  The path of the Docs place, in one project or, for nil, all of them,
  showing the notebooks as `docs` says: on a canvas arranged as `arrange` and
  `every` say, or as a list (`view: :list`).
  """
  def docs_path(fleet_id, project, docs) do
    canvas? = docs.view == :canvas

    with_query(
      "#{Regents.Keyfleet.Fleets.path(fleet_id)}/workspace",
      given(
        [place: :docs, project: project, view: if(not canvas?, do: "list")] ++
          if(canvas?, do: arrangement(docs), else: [])
      )
    )
  end

  # A canvas's arrangement in its address, left out where it is the first one.
  defp arrangement(%{arrange: arrange, every: every}),
    do: [arrange: if(arrange != :time, do: arrange), every: if(every != :day, do: every)]

  @doc "The address a workspace cites one commit of a project's repository by."
  def commit_url(fleet_id, repository, hash),
    do: Endpoint.url() <> Code.commit_path(fleet_id, repository, hash)

  defp given(query), do: Enum.reject(query, &is_nil(elem(&1, 1)))

  defp with_query(path, []), do: path
  defp with_query(path, query), do: path <> "?" <> URI.encode_query(query)

  @doc """
  The place of the workspace the address names (`place`), the Project, Docs,
  Code or Public, in the project it names (`project`) or across all of them;
  beside it the fleet's projects, for the picker, and the Key the member
  acts as (`you`) with the projects it holds. Any other place, or a project
  the fleet doesn't have, is a page that doesn't exist, and a visitor learns
  neither. Anyone reads the Public place; a visitor reads every other place
  as the members-only page.
  """
  def board(fleet_id, params, actor) do
    place = Map.get(@places, params["place"]) || raise NotFoundError
    opts = [actor: actor]

    with {:ok, fleet} <- fleet(fleet_id, opts),
         {:ok, projects} <- members_read(fleet, Projects.by_state(fleet_id, opts)) do
      shown = shown_project!(projects, params["project"])

      fleet
      |> place(place, shown, projects, params, opts)
      |> Map.merge(%{
        fleet_id: fleet_id,
        fleet_name: fleet.name,
        place: place,
        project: shown && shown.name,
        active?: is_nil(shown) or shown.state == :active,
        projects:
          Enum.map(
            projects,
            &Map.take(&1, [
              :name,
              :title,
              :description,
              :key,
              :created_by_key,
              :state,
              :shown_to_everyone
            ])
          ),
        you: you(projects, actor, fleet_id)
      })
    else
      {:missing, _name} -> raise NotFoundError
      {:members_only, name} when place == :public -> public_board(fleet_id, name, params)
      {:members_only, name} -> members_only(fleet_id, name)
    end
  end

  # The Public place as a visitor reads it, with the projects as their pages
  # show them.
  defp public_board(fleet_id, name, params) do
    projects = Projects.project_titles!(fleet_id)
    shown = shown_project!(projects, params["project"])

    fleet_id
    |> public(shown, projects, nil, params)
    |> Map.merge(%{
      fleet_id: fleet_id,
      fleet_name: name,
      place: :public,
      project: shown && shown.name,
      active?: is_nil(shown) or shown.state == :active,
      projects:
        Enum.map(
          projects,
          &Map.take(&1, [:name, :title, :description, :key, :state, :shown_to_everyone])
        ),
      you: nil,
      rooms: []
    })
  end

  defp shown_project!(_projects, nil), do: nil

  defp shown_project!(projects, name),
    do: Enum.find(projects, &(&1.name == name)) || raise(NotFoundError)

  # The Key the member acts as (`Regents.Keyfleet.Keys.identity/2`), its active
  # project and its archived ones; nil for a member who holds no Key.
  defp you(projects, actor, fleet_id) do
    with %{token_id: key} <- Keys.identity(actor, fleet_id) do
      held = Enum.filter(projects, &(&1.key == key))

      %{
        key: key,
        active: Enum.find_value(held, &(&1.state == :active && &1.name)),
        archived: for(%{state: :archived, name: name} <- held, do: name)
      }
    end
  end

  # The small panels under the Graph view's stage, the project's or the whole
  # fleet's: the newest lines of the workstream, and the newest notebooks and
  # code the fleet's members pinned, a few of each. None of it calls the
  # notebook hub or the code store.
  defp instruments(fleet_id, filter, projects, opts) do
    activity =
      fleet_id
      |> Graph.latest_activity!(%{project: filter.project}, opts)
      |> Enum.take(@instrument_rows)

    titles = titles(fleet_id, Enum.flat_map(activity, &mentions/1), opts)
    agents = agent_names(Enum.map(activity, &actor_wallet/1))
    hub? = Notebooks.hub?(fleet_id)
    spaces = Map.new(projects, &{&1.name, hub? && &1.hub_project_id})
    repositories = Map.new(projects, &{&1.name, &1.repository})
    labels = if filter.project, do: %{}, else: Map.new(projects, &{&1.name, &1.title})

    %{
      workstream: Enum.map(activity, &line(&1, titles, agents)),
      docs:
        for pin <- shown_pins(Graph.pins!(fleet_id, :docs, filter.project, opts), spaces) do
          space = spaces[pin.project]
          link = if is_binary(space), do: notebook_link(fleet_id, space, pin.target)
          pin_row(pin, link, labels, opts[:actor])
        end,
      code:
        for pin <- shown_pins(Graph.pins!(fleet_id, :code, filter.project, opts), repositories) do
          link = Code.files_path(fleet_id, repositories[pin.project], pin.target)
          pin_row(pin, link, labels, opts[:actor])
        end
    }
  end

  # The tasks awaiting review, the project's or the whole fleet's, the
  # longest wait first, a few of them, each with when its wait began.
  defp awaiting_review(fleet_id, within, opts) do
    for task <-
          Graph.awaiting_review!(fleet_id, within, [query: [limit: @instrument_rows]] ++ opts),
        do: %{
          id: task.id,
          title: task.title,
          at: time(task.changed_at),
          path: item_path(fleet_id, task.id)
        }
  end

  # The newest pins of the projects listed, a few of them.
  defp shown_pins(pins, projects),
    do: pins |> Enum.filter(&Map.has_key?(projects, &1.project)) |> Enum.take(@instrument_rows)

  # The goals the Graph view steps through, one goal's map at a time: the
  # project's, or the whole fleet's, the #{@step_goals} most recently changed,
  # in the order they were added. A step shows the goal's whole map, so it
  # leaves the kind and owner filters behind.
  defp step_goals(fleet_id, filter, opts) do
    fleet_id
    |> Graph.graph_objects!(
      %{project: filter.project, type: "goal", archived: filter.archived?},
      [query: [limit: @step_goals]] ++ opts
    )
    |> Enum.sort_by(fn %{id: "goal#" <> number} -> String.to_integer(number) end)
    |> Enum.map(
      &%{
        id: &1.id,
        title: &1.title,
        path: board_path(fleet_id, %{filter | goal: &1.id, type: nil, owner: nil})
      }
    )
  end

  # Each project's title by its name, to label what the whole fleet's view
  # lists; none in one project's.
  defp labels(nil, projects), do: Map.new(projects, &{&1.name, &1.title})
  defp labels(_shown, _projects), do: %{}

  # The project's items, or the whole fleet's, with the links between them
  # (`RegentsWeb.Keyfleet.WorkspaceGraph`), for the tree canvas with when each was
  # made, read from one snapshot, under how many goals and tasks stand where
  # (`Regents.Keyfleet.Graph.tally/3`).
  defp place(fleet, :project, shown, projects, params, opts)
       when is_map_key(params, "view") do
    filter = filter!(params, shown)

    case ready(fleet, opts) do
      {:ready, cursor} ->
        {:ok, {graph, created}} =
          Graph.in_snapshot(fn ->
            graph =
              Graph.workspace_graph!(
                fleet.id,
                %{
                  project: filter.project,
                  type: filter.type,
                  owner_key: filter.owner,
                  goal: filter.goal,
                  archived: filter.archived?
                },
                opts
              )

            made =
              fleet.id
              |> Graph.object_titles!(
                Enum.map(graph.nodes, & &1.id),
                [load: [:created_at]] ++ opts
              )
              |> Map.new(&{&1.id, &1.created_at})

            {graph, made}
          end)

        items = WorkspaceGraph.items(graph, fleet.id, labels(shown, projects))

        %{
          ready?: true,
          seen: seen(cursor),
          filter: filter,
          counts: Graph.tally!(fleet.id, filter.project, opts),
          graph: items,
          canvas: WorkspaceGraph.canvas(items, created),
          goals: step_goals(fleet.id, filter, opts),
          instruments: instruments(fleet.id, filter, projects, opts)
        }

      {:missing, _name} ->
        %{ready?: false, seen: nil, filter: filter}
    end
  end

  # The project's items, or the whole fleet's, a page of them, beside its
  # goals, its latest changes and how many goals and tasks stand where
  # (`Regents.Keyfleet.Graph.tally/3`).
  defp place(fleet, :project, shown, projects, params, opts) do
    filter = filter!(params, shown)
    within = %{project: filter.project}
    labels = labels(shown, projects)

    case ready(fleet, opts) do
      {:ready, cursor} ->
        page = page!(cards_page(fleet, filter, params, opts))
        activity = Graph.latest_activity!(fleet.id, within, opts)
        titles = titles(fleet.id, Enum.flat_map(activity, &mentions/1), opts)

        goals =
          fleet.id
          |> Graph.workspace_cards!(
            Map.put(within, :type, "goal"),
            Keyword.put(opts, :page, limit: @board_goals)
          )
          |> Map.fetch!(:results)

        agents =
          agent_names(
            Enum.map(page.results, &creator_wallet(&1.sys)) ++
              Enum.map(activity, &actor_wallet/1)
          )

        notes =
          fleet.id
          |> Graph.workspace_cards!(
            Map.put(within, :type, "note"),
            Keyword.put(opts, :page, limit: 24)
          )
          |> Map.fetch!(:results)
          |> Map.new(&{&1.changed_seq, &1.card["gist"]})

        %{
          ready?: true,
          seen: seen(cursor),
          filter: filter,
          counts: Graph.tally!(fleet.id, filter.project, opts),
          cards: Enum.map(page.results, &entry(&1, filter, fleet.id, agents, labels)),
          goals: Enum.map(goals, &goal_row(&1, labels)),
          all_goals: board_path(fleet.id, %{filter | type: "goal", archived?: false}),
          first_page?: not paged?(params),
          first_page: board_path(fleet.id, filter),
          pages: page_links(page, params, &board_path(fleet.id, filter, &1)),
          activity: Enum.map(activity, &Map.put(line(&1, titles, agents), :note, notes[&1.seq])),
          reviews: awaiting_review(fleet.id, within, opts)
        }

      {:missing, _name} ->
        %{ready?: false, seen: nil, filter: filter}
    end
  end

  # One project's newest notebooks, each locked or open to every member's
  # edits, with whether the member is the one who locks it, and the daily
  # copies of them the member may bring back; or each project's few newest in
  # turn; and what the fleet's members pinned there. Each notebook shown says
  # whether it changed since its newest kept run page (`since_run/2`), all of
  # them from one read. On the canvas (`docs.view`), the notebooks shown are
  # its cards as well (`notebook_canvas/3`). None of it comes from the
  # workspace's log, so it keeps no place in it (`seen`), and its notices
  # don't read it again.
  defp place(fleet, :docs, shown, projects, params, opts) do
    docs = docs!(params)
    hub? = Notebooks.hub?(fleet.id)
    spaces = Map.new(projects, &{&1.name, hub? && &1.hub_project_id})
    labels = labels(shown, projects)
    shown_hub? = hub? and shown != nil

    notebooks =
      shown &&
        fleet.id
        |> notebooks(spaces[shown.name], limit: @docs_shown)
        |> with_locks(fleet.id, shown_hub?, opts[:actor])

    sections = if(is_nil(shown), do: sections(fleet.id, projects, spaces, docs), else: [])
    pages = run_pages(fleet.id, on_show(notebooks, sections))
    notebooks = since_run(notebooks, pages)
    sections = Enum.map(sections, &%{&1 | notebooks: since_run(&1.notebooks, pages)})

    %{
      docs: docs,
      hub?: hub?,
      notebooks: notebooks,
      copies: if(shown_hub?, do: copies(fleet.id, opts[:actor], shown.name), else: []),
      sections: sections,
      canvas: docs_canvas(fleet.id, hub?, docs, notebooks, sections, opts),
      pins:
        for pin <- Graph.pins!(fleet.id, :docs, shown && shown.name, opts),
            Map.has_key?(spaces, pin.project) do
          space = spaces[pin.project]
          link = if is_binary(space), do: notebook_link(fleet.id, space, pin.target)
          pin_row(pin, link, labels, opts[:actor])
        end
    }
  end

  # One project's repository: how to copy it, its top folder, the changes
  # sent to it lately, and what the fleet's members pinned in it.
  defp place(fleet, :code, %{} = project, _projects, _params, opts) do
    repository = project.repository

    %{
      repository: repository,
      clone_url: Code.clone_url(repository),
      history_link: Code.history_path(fleet.id, repository),
      pushes: pushes(Code.recent_pushes!(fleet.id, project.name, opts), fleet.id, repository),
      files: folder_entries(fleet.id, repository, ""),
      repositories: [],
      pins:
        for pin <- Graph.pins!(fleet.id, :code, project.name, opts) do
          link = Code.files_path(fleet.id, repository, pin.target)
          pin_row(pin, link, %{}, opts[:actor])
        end
    }
  end

  # Every project's repository in turn, each with how to copy it, and every
  # pin in the fleet's code.
  defp place(fleet, :code, nil, projects, _params, opts) do
    repositories = Map.new(projects, &{&1.name, &1.repository})
    labels = labels(nil, projects)

    %{
      repositories:
        for project <- projects do
          %{
            project: project.name,
            title: project.title,
            key: project.key,
            state: project.state,
            clone_url: Code.clone_url(project.repository),
            link: place_path(fleet.id, :code, project.name)
          }
        end,
      pins:
        for pin <- Graph.pins!(fleet.id, :code, nil, opts),
            Map.has_key?(repositories, pin.project) do
          link = Code.files_path(fleet.id, repositories[pin.project], pin.target)
          pin_row(pin, link, labels, opts[:actor])
        end
    }
  end

  # What the fleet's Keys made public, in the project on show or every
  # project, and the rooms the member's Key makes its posts public from.
  defp place(fleet, :public, shown, projects, params, opts) do
    you = you(projects, opts[:actor], fleet.id)

    fleet.id
    |> public(shown, projects, you && you.key, params)
    |> Map.put(
      :rooms,
      if(you,
        do: for(room <- Rooms.list_rooms!(fleet.id, opts), do: room_choice(room)),
        else: []
      )
    )
  end

  defp pin_row(pin, link, labels, actor) do
    %{
      id: pin.id,
      project: pin.project,
      label: labels[pin.project],
      target: pin.target,
      title: pin.title,
      folder?: pin.folder?,
      link: link,
      whose: whose(pin, actor)
    }
  end

  # Newest first, each with what a visitor reads of it: for posts, the posts
  # its Key wrote in that range of the room, word for word, each with its
  # writer; for an item, the item as it stands, while it isn't archived; for
  # a saved notebook page, its address, which opens for anyone; for a commit,
  # the project's files at it, read-only. Only the Key that made it public
  # (`key`) takes it back. A page at a time,
  # `@public_shown` long: `more` reads on from the last one, and `first` goes
  # back to the newest.
  defp public(fleet_id, shown, projects, key, params) do
    labels = labels(shown, projects)
    project = shown && shown.name
    from = Map.take(params, ["after"])

    %Ash.Page.Keyset{results: publications, more?: more?} =
      fleet_id
      |> Projects.publications(project, page: [limit: @public_shown] ++ public_position(from))
      |> page!()

    rooms =
      fleet_id
      |> Rooms.list_rooms!(authorize?: false)
      |> Map.new(&{&1.slug, RoomsLive.room_label(&1)})

    objects = public_objects(fleet_id, for(%{kind: :item, item: id} <- publications, do: id))
    agents = agent_names(for {_id, object} <- objects, do: creator_wallet(object.sys))

    %{
      public:
        Enum.flat_map(publications, fn publication ->
          case public_record(publication, rooms, objects, agents) do
            nil ->
              []

            record ->
              [
                Map.merge(record, %{
                  id: publication.id,
                  kind: publication.kind,
                  project: publication.project,
                  label: labels[publication.project],
                  key: publication.key,
                  at: publication.inserted_at,
                  mine?: publication.key == key
                })
              ]
          end
        end),
      public_more:
        if(more?,
          do: public_path(fleet_id, project, after: List.last(publications).__metadata__.keyset)
        ),
      public_first: if(from != %{}, do: public_path(fleet_id, project, []))
    }
  end

  defp public_position(%{"after" => keyset}) when is_binary(keyset), do: [after: keyset]
  defp public_position(_newest), do: []

  defp public_path(fleet_id, project, position),
    do:
      with_query(
        "#{Regents.Keyfleet.Fleets.path(fleet_id)}/workspace",
        given([place: "public", project: project] ++ position)
      )

  defp public_record(%{kind: :posts} = publication, rooms, _objects, _agents) do
    posts =
      for post <-
            Publish.posts(
              publication.fleet_id,
              publication.room,
              publication.from_seq,
              publication.to_seq,
              publication.key,
              publication.author_wallet
            ),
          do: Message.public(post, post.reply_to_seq)

    %{
      agent: Enum.find_value(posts, &(&1.author.kind == :agent && &1.author.name)),
      room: publication.room,
      room_label: Map.get(rooms, publication.room, publication.room),
      from: publication.from_seq,
      to: publication.to_seq,
      posts: posts
    }
  end

  # An item archived since it was made public stops showing.
  defp public_record(%{kind: :item, item: id}, _rooms, objects, agents) do
    case objects[id] do
      %{sys: %{"archived" => true}} -> nil
      nil -> nil
      object -> %{item: public_item(object, agents)}
    end
  end

  defp public_record(%{kind: :page} = publication, _rooms, _objects, _agents),
    do: %{page_url: Notebooks.url(publication.fleet_id, publication.page)}

  defp public_record(%{kind: :commit} = publication, _rooms, _objects, _agents) do
    case Code.repository(publication.fleet_id, publication.project) do
      {:ok, repository} when is_binary(repository) ->
        %{
          commit: publication.commit_hash,
          files_url:
            Code.files_path(publication.fleet_id, repository, "", publication.commit_hash)
        }

      _gone ->
        nil
    end
  end

  defp public_objects(_fleet_id, []), do: %{}

  defp public_objects(fleet_id, ids),
    do: fleet_id |> Graph.read_objects!(ids, actor: %System{}) |> Map.new(&{&1.id, &1})

  # What a visitor reads of an item: its words and choices, each address as
  # written, never a link into the members' pages.
  defp public_item(object, agents) do
    %{
      type: object.type,
      title: object.data["title"],
      by: created_by(object.sys, agents),
      changed_at: time(object.changed_at),
      fields:
        Enum.flat_map(Map.get(@fields, object.type, []), fn {field, label} ->
          case public_value(field, object.data[field]) do
            nil -> []
            shown -> [{label, shown}]
          end
        end)
    }
  end

  defp public_value(_field, nil), do: nil
  defp public_value(_field, []), do: nil

  defp public_value(field, value) when is_map_key(@choices, field), do: choice(field, value)
  defp public_value(_field, value), do: value(value)

  defp room_choice(room), do: %{slug: room.slug, label: RoomsLive.room_label(room)}

  # Whose a pin is to the member reading: only its pinner lifts it.
  defp whose(pin, actor),
    do: if(pin.human_account_id == actor.human_account_id, do: :mine, else: :theirs)

  # Each project's newest few notebooks, the projects read at once; one the
  # hub doesn't answer in time is `:unreadable`.
  defp sections(fleet_id, projects, spaces, docs) do
    projects
    |> Task.async_stream(&notebooks(fleet_id, spaces[&1.name], limit: @section_shown),
      max_concurrency: 4,
      timeout: Notebooks.config()[:page_timeout_ms],
      on_timeout: :kill_task
    )
    |> Enum.zip_with(projects, fn
      {:ok, notebooks}, project ->
        section(fleet_id, project, notebooks, docs)

      {:exit, :timeout}, project ->
        Logger.warning("The notebooks of #{fleet_id} could not be read: timeout")
        section(fleet_id, project, :unreadable, docs)
    end)
  end

  defp section(fleet_id, project, notebooks, docs) do
    %{
      project: project.name,
      title: project.title,
      key: project.key,
      state: project.state,
      notebooks: notebooks,
      link: docs_path(fleet_id, project.name, docs)
    }
  end

  # The Docs place's notebooks on show: the project's, or with no project
  # shown, each section's (the one not on show is nil or empty).
  defp on_show(notebooks, sections),
    do: readable(notebooks) ++ Enum.flat_map(sections, &readable(&1.notebooks))

  # The Docs place's canvas, when the fleet has a notebook hub and the canvas
  # is the view: the notebooks on show.
  defp docs_canvas(fleet_id, true, %{view: :canvas}, notebooks, sections, opts),
    do: notebook_canvas(fleet_id, on_show(notebooks, sections), opts)

  defp docs_canvas(_fleet_id, _hub?, _docs, _notebooks, _sections, _opts), do: nil

  # The notebooks shown as a tree canvas's cards, the #{@canvas_notebooks}
  # most recently changed, each headed by the Key that made it
  # (`Regents.Keyfleet.Notebooks.keys/2`), standing "Changed" while it changed since
  # its newest kept run page; and the tasks that name one of them as their
  # notebook (`notebook_ref`), each linked from its notebook. The hub keeps
  # nothing of which notebook another was made from, so notebooks link to
  # nothing else.
  defp notebook_canvas(fleet_id, notebooks, opts) do
    notebooks =
      notebooks
      |> Enum.sort_by(& &1.changed, :desc)
      |> Enum.take(@canvas_notebooks)

    keys = Notebooks.keys(fleet_id, notebooks)
    by_url = Map.new(notebooks, &{&1.url, &1.id})

    tasks =
      if notebooks == [],
        do: [],
        else: Graph.tasks_naming_notebooks!(fleet_id, Map.keys(by_url), opts)

    %{
      cards:
        Enum.map(notebooks, fn notebook ->
          %{
            id: notebook.id,
            kind: "Notebook",
            title: notebook.title,
            href: notebook.open,
            patch: false,
            tone: :plain,
            standing: if(notebook.changed_since_run?, do: "Changed"),
            author: key_label(keys[notebook.id]),
            created: notebook.added,
            changed: notebook.changed,
            archived: false,
            folder: notebook.folder
          }
        end) ++
          Enum.map(tasks, fn task ->
            %{
              id: task.id,
              kind: "Task",
              title: task.title,
              href: item_path(fleet_id, task.id),
              patch: true,
              tone: WorkspaceGraph.tone(task.standing),
              standing: WorkspaceGraph.standing_name(task.standing),
              author: key_label(task.owner_key),
              created: task.created_at,
              changed: task.changed_at,
              archived: false,
              folder: nil
            }
          end),
      links:
        Enum.map(
          tasks,
          &%{
            id: &1.id <> " notebook",
            type: "notebook",
            from: Map.fetch!(by_url, &1.data["notebook_ref"]),
            to: &1.id
          }
        )
    }
  end

  # The notebooks read, none when there are none or they can't be read.
  defp readable(notebooks) when is_list(notebooks), do: notebooks
  defp readable(_none_or_unreadable), do: []

  defp key_label(nil), do: "No Key"
  defp key_label(key), do: ActivityLines.key_name(key, nil)

  @doc """
  One item, a page of its links and a page of its history. A goal comes with
  the work around it (`goal`) in place of its links.
  """
  def item(fleet_id, object_id, params, actor) do
    opts = [actor: actor]
    links_at = position!(params, "links")
    history_through = history_position!(params)

    with {:ok, fleet} <- fleet(fleet_id, opts),
         {:ok, object} <-
           members_read(fleet, Graph.read_object(fleet_id, object_id, [load: [:review]] ++ opts)),
         {:ready, cursor} <- ready(fleet, opts) do
      base = %{fleet_id: fleet_id, fleet_name: fleet.name, ready?: true, seen: seen(cursor)}

      case object do
        nil ->
          Map.put(base, :object, nil)

        object ->
          {links, goal} = around(object, fleet_id, links_at, opts)

          {history, earlier} =
            fleet_id
            |> Graph.object_history(object_id, history_through, actor: actor)
            |> page!()
            |> Enum.split(50)

          titles =
            titles(
              fleet_id,
              other_ends(links, object_id) ++ Enum.flat_map(history, &mentions/1),
              opts
            )

          agents =
            agent_names(
              [creator_wallet(object.sys) | joined_wallets(object.sys)] ++
                Enum.map(history, &actor_wallet/1)
            )

          path = &item_path(fleet_id, object_id, item_query(params, &1, &2))

          Map.merge(base, %{
            object: detail(object, fleet_id, agents, opts),
            public: item_public(fleet_id, object, actor),
            goal: goal,
            links: links && link_rows(links, object, titles, path, links_at != []),
            history: %{
              lines: Enum.map(history, &line(&1, titles, agents)),
              more: if(earlier != [], do: path.("history", List.last(history).seq - 1)),
              first: if(history_through != %{}, do: path.("history", nil))
            }
          })
      end
    else
      {:missing, name} -> %{fleet_id: fleet_id, fleet_name: name, ready?: false, seen: nil}
      {:members_only, name} -> members_only(fleet_id, name)
    end
  end

  # Whether everyone reads the item on the Public place, and what the
  # member's Key does about it: the Key that added it makes it public, and
  # the Key that made it public takes it back.
  defp item_public(fleet_id, object, actor) do
    publication = Projects.item_publication!(fleet_id, object.id, actor: actor)
    key = with %{token_id: key} <- Keys.identity(actor, fleet_id), do: key
    added_by = get_in(object.sys, ["created_by", "key", "token_id"])

    %{
      id: publication && publication.id,
      link: place_path(fleet_id, :public, object.project),
      take_back?: publication != nil and publication.key == key,
      make?:
        is_nil(publication) and is_integer(key) and added_by == key and
          not archived?(object.sys)
    }
  end

  # A goal's page lists the work around it in place of its links.
  defp around(%{type: "goal"} = goal, fleet_id, _links_at, opts),
    do: {nil, goal_work(fleet_id, goal, opts)}

  defp around(object, fleet_id, links_at, opts) do
    {page!(Graph.object_links(fleet_id, object.id, [page: links_at ++ [limit: 50]] ++ opts)), nil}
  end

  defp other_ends(nil, _object_id), do: []
  defp other_ends(links, object_id), do: Enum.map(links.results, &other_end(&1, object_id))

  defp link_rows(links, object, titles, path, later?) do
    %{
      rows: Enum.map(links.results, &link_row(&1, object, titles)),
      more: if(links.more?, do: path.("links", List.last(links.results).__metadata__.keyset)),
      first: if(later?, do: path.("links", nil))
    }
  end

  defp members_only(fleet_id, name) do
    %{
      fleet_id: fleet_id,
      fleet_name: name,
      members_only?: true,
      seen: nil,
      projects: FleetPage.read_recent_work(fleet_id)
    }
  end

  # Every goal starts open, so only one that has moved on says so.
  defp goal_standing(status) when status in [nil, "open"], do: nil
  defp goal_standing(status), do: choice("status", status)

  @doc """
  One page of a project's repository history, newest first, named by the
  repository: from the commit `from` (a full hash, so the pages hold still
  while changes arrive) or the default branch now, `page` by `page`. Each
  commit with its first line, its git author, when it was written, the Key
  and agent that sent it, and the tasks and evidence that cite it. `commits`
  is `:unreadable` when the code store doesn't answer. An address naming a
  repository none of the fleet's projects has, a `from` that isn't a full
  hash or a commit there, or a page past the history's end is a page that
  doesn't exist.
  """
  def history(fleet_id, repository, from, page, actor) do
    from = commit!(from)
    page = history_page!(page)
    project = project_of!(fleet_id, repository)
    opts = [actor: actor]

    # Reading who sent no commit at all still asks whether the reader is
    # one of the fleet's members.
    with {:ok, fleet} <- fleet(fleet_id, opts),
         {:ok, _members} <- members_read(fleet, Code.senders(fleet_id, project.name, [], opts)) do
      fleet_id
      |> history_page(repository, project, from, page, opts)
      |> Map.merge(%{
        fleet_id: fleet_id,
        fleet_name: fleet.name,
        repository: repository,
        project: project.name,
        page: page,
        files_link: Code.files_path(fleet_id, repository, "")
      })
    else
      {:missing, _name} ->
        raise NotFoundError

      {:members_only, name} ->
        %{fleet_id: fleet_id, fleet_name: name, members_only?: true}
    end
  end

  defp history_page(fleet_id, repository, project, from, page, opts) do
    case Code.history(repository, from, (page - 1) * @history_page, @history_page) do
      {:ok, %{commits: []}} when page > 1 ->
        raise NotFoundError

      {:ok, %{commits: commits, head: head, more?: more?}} ->
        hashes = Enum.map(commits, & &1["hash"])
        senders = Code.senders!(fleet_id, project.name, hashes, opts)
        agents = agent_names(senders |> Map.values() |> Enum.map(& &1.acting_agent_wallet))

        citing =
          citing_any(fleet_id, Enum.map(hashes, &commit_url(fleet_id, repository, &1)), opts)

        %{
          commits:
            Enum.map(commits, &history_row(&1, fleet_id, repository, senders, agents, citing)),
          head: head,
          more?: more?,
          newer: if(page > 1, do: Code.history_path(fleet_id, repository, head, page - 1)),
          older:
            if(more? and page < @history_pages,
              do: Code.history_path(fleet_id, repository, head, page + 1)
            ),
          latest: if(from, do: Code.history_path(fleet_id, repository))
        }

      :not_found ->
        raise NotFoundError

      {:error, error} ->
        %{
          commits: unreadable_code(repository, error),
          head: nil,
          more?: false,
          newer: nil,
          older: nil,
          latest: nil
        }
    end
  end

  defp history_row(commit, fleet_id, repository, senders, agents, citing) do
    hash = commit["hash"]

    %{
      hash: hash,
      subject: commit["message"],
      author: commit["author"],
      at: time(commit["date"]),
      link: Code.commit_path(fleet_id, repository, hash),
      sent: sender(senders[hash], agents),
      citing: Map.get(citing, commit_url(fleet_id, repository, hash), [])
    }
  end

  # Who sent a commit: the Key, the agent beside it when one sent it, the
  # branch it came on and when.
  defp sender(nil, _agents), do: nil

  defp sender(push, agents) do
    %{
      token_id: push.token_id,
      agent: agents[push.acting_agent_wallet],
      ref: push.ref,
      what: moved(push.ref),
      at: push.pushed_at
    }
  end

  # The tasks and evidence that cite each address, by address, each as a
  # link to it.
  defp citing_any(_fleet_id, [], _opts), do: %{}

  defp citing_any(fleet_id, urls, opts) do
    fleet_id
    |> Graph.work_citing_any!(urls, opts)
    |> Enum.reject(&archived?(&1.sys))
    |> Enum.group_by(
      &if(&1.type == "task", do: &1.data["commit_ref"], else: &1.data["source_uri"]),
      &%{id: &1.id, type: &1.type, title: &1.title}
    )
  end

  defp history_page!(page) when page in 1..@history_pages, do: page
  defp history_page!(_page), do: raise(NotFoundError)

  @doc """
  The page a History address names: 1 when it names none. A page that isn't
  a whole number is a page that doesn't exist.
  """
  def history_page_number!(nil), do: 1

  def history_page_number!(page) do
    case Integer.parse(page) do
      {page, ""} -> page
      _not_a_page -> raise NotFoundError
    end
  end

  @doc """
  One commit of one of the fleet's repositories, named by the repository and
  its full hash: its message, its git author and when it was written, the
  Key and agent that sent it, the commits before it, and each file it
  changed with the lines that changed; beside it the tasks that name it as
  their commit, with the notebook and result each names, and the evidence
  that cites it with the tasks that produced that evidence. `change` is
  `:not_found` while the code holds no commit by that hash, and
  `:unreadable` when the code store doesn't answer. An address naming a
  repository none of the fleet's projects has, or less than a full hash, is
  a page that doesn't exist.
  """
  def commit(fleet_id, repository, hash, actor) do
    if not Code.full_hash?(hash), do: raise(NotFoundError)
    project = project_of!(fleet_id, repository)
    opts = [actor: actor]
    url = commit_url(fleet_id, repository, hash)

    with {:ok, fleet} <- fleet(fleet_id, opts),
         {:ok, senders} <-
           members_read(fleet, Code.senders(fleet_id, project.name, [hash], opts)),
         {:ok, citing} <- members_read(fleet, Graph.work_citing(fleet_id, url, opts)) do
      producers = producers(fleet_id, Enum.filter(citing, &(&1.type == "evidence")), opts)
      titles = titles(fleet_id, producers |> Map.values() |> List.flatten(), opts)

      agents =
        agent_names([
          senders[hash] && senders[hash].acting_agent_wallet
          | Enum.map(citing, &creator_wallet(&1.sys))
        ])

      %{
        fleet_id: fleet_id,
        fleet_name: fleet.name,
        hash: hash,
        project: project.name,
        public: commit_public(fleet_id, project, repository, hash, actor),
        url: url,
        repository: repository,
        clone_url: Code.clone_url(repository),
        sent: sender(senders[hash], agents),
        change: commit_change(fleet_id, repository, hash),
        history_link: Code.history_path(fleet_id, repository),
        files_link: Code.files_path(fleet_id, repository, "", hash),
        citing:
          for object <- citing do
            %{
              id: object.id,
              type: object.type,
              title: object.title,
              excerpt: object.card["gist"],
              archived?: archived?(object.sys),
              by: created_by(object.sys, agents),
              notebook_ref: task_ref(object, "notebook_ref"),
              result_ref: task_ref(object, "result_ref"),
              notebook: source(task_ref(object, "notebook_ref"), fleet_id),
              result: source(task_ref(object, "result_ref"), fleet_id),
              tasks: Enum.map(Map.get(producers, object.id, []), &item_part(&1, titles))
            }
          end
      }
    else
      {:missing, _name} ->
        raise NotFoundError

      {:members_only, name} ->
        %{fleet_id: fleet_id, fleet_name: name, hash: hash, members_only?: true}
    end
  end

  # Whether everyone reads the project's code at this commit, and what the
  # member's Key does about it: the Key holding the active project makes it
  # public, and the Key that made it public takes it back.
  defp commit_public(fleet_id, project, repository, hash, actor) do
    publication = Projects.commit_publication!(fleet_id, project.name, hash, actor: actor)
    key = with %{token_id: key} <- Keys.identity(actor, fleet_id), do: key

    %{
      id: publication && publication.id,
      link: Code.files_path(fleet_id, repository, "", hash),
      take_back?: publication != nil and publication.key == key,
      make?:
        is_nil(publication) and is_integer(key) and project.key == key and
          project.state == :active
    }
  end

  # The notebook or result a task names, for a task.
  defp task_ref(%{type: "task", data: data}, field), do: data[field]
  defp task_ref(_object, _field), do: nil

  # The commit as the code holds it: its message split into the first line
  # and the rest, its author and time, its parents, and each file it changed
  # with its lines.
  defp commit_change(fleet_id, repository, hash) do
    case Code.commit(repository, hash) do
      {:ok, commit} ->
        {subject, body} = message(commit["message"])
        files = commit["files"] |> Enum.with_index() |> Enum.map(&changed_file/1)

        %{
          subject: subject,
          body: body,
          author: commit["author"],
          at: time(commit["date"]),
          parents:
            for parent <- commit["parents"] do
              %{hash: parent, link: Code.commit_path(fleet_id, repository, parent)}
            end,
          files: files,
          files_cut?: commit["files_truncated"] == true,
          additions: files |> Enum.map(&(&1.additions || 0)) |> Enum.sum(),
          deletions: files |> Enum.map(&(&1.deletions || 0)) |> Enum.sum()
        }

      :not_found ->
        :not_found

      {:error, error} ->
        unreadable_code(repository, error)
    end
  end

  defp message(message) do
    case String.split(message, "\n", parts: 2) do
      [subject] -> {subject, nil}
      [subject, body] -> {subject, if(String.trim(body) != "", do: String.trim(body))}
    end
  end

  defp changed_file({file, index}) do
    %{
      id: index,
      path: file["path"],
      old_path: file["old_path"],
      status: file["status"],
      additions: file["additions"],
      deletions: file["deletions"],
      binary?: file["binary"] == true,
      patch: file["patch"],
      cut?: file["patch_truncated"] == true
    }
  end

  @doc """
  One folder or file of a project's repository as it stands on the default
  branch now, or at the commit `at` asks for, named by the repository and the
  `path` asked for (none for the top folder): a folder's names, folders
  first, or a file's text, beside the latest changes sent to the repository.
  A visitor reads a commit the Key holding the project made public, read-only,
  and nothing else of the code. A file that isn't text, or is past
  `file_max_bytes`, is named but not shown; `listing` is `:unreadable`
  when the code store doesn't answer. An address naming a repository none
  of the fleet's projects has, a path that can't name a place in the code,
  or a file that isn't there is a page that doesn't exist.
  """
  def files(fleet_id, repository, params, actor) do
    path = code_path!(params["path"])
    at = commit!(params["at"])
    project = project_of!(fleet_id, repository)
    opts = [actor: actor]

    with {:ok, fleet} <- fleet(fleet_id, opts),
         {:ok, pushes} <- members_read(fleet, Code.recent_pushes(fleet_id, project.name, opts)) do
      %{
        fleet_id: fleet_id,
        fleet_name: fleet.name,
        repository: repository,
        path: path,
        at: at,
        project: project.name,
        active?: project.state == :active and is_nil(at),
        pinned:
          if(at,
            do: %{},
            else:
              fleet_id
              |> Graph.pins!(:code, project.name, opts)
              |> Map.new(&{&1.target, whose(&1, actor)})
          ),
        crumbs: crumbs(fleet_id, repository, path, at),
        clone_url: Code.clone_url(repository),
        pushes: if(at, do: [], else: pushes(pushes, fleet_id, repository)),
        listing: listing(fleet_id, repository, path, at),
        history_link: Code.history_path(fleet_id, repository),
        commit_link: at && Code.commit_path(fleet_id, repository, at)
      }
    else
      {:missing, _name} ->
        raise NotFoundError

      {:members_only, name} ->
        if at && Projects.commit_publication!(fleet_id, project.name, at, actor: %System{}),
          do: public_files(fleet_id, name, repository, project, path, at),
          else: %{fleet_id: fleet_id, fleet_name: name, path: path, members_only?: true}
    end
  end

  defp code_path!(nil), do: ""
  defp code_path!(path), do: if(Code.code_path?(path), do: path, else: raise(NotFoundError))

  defp commit!(nil), do: nil
  defp commit!(hash), do: if(Code.full_hash?(hash), do: hash, else: raise(NotFoundError))

  # A commit the Key holding the project made public, as a visitor reads it:
  # its files and folders alone.
  defp public_files(fleet_id, name, repository, project, path, at) do
    %{
      fleet_id: fleet_id,
      fleet_name: name,
      repository: repository,
      path: path,
      at: at,
      project: project.name,
      active?: false,
      pinned: %{},
      crumbs: crumbs(fleet_id, repository, path, at),
      clone_url: nil,
      pushes: [],
      listing: listing(fleet_id, repository, path, at),
      history_link: nil,
      commit_link: nil
    }
  end

  # The project whose repository an address names, if it is one of the
  # fleet's.
  defp project_of!(fleet_id, repository) do
    case Projects.project_of_repository!(repository, actor: %System{}) do
      %{fleet_id: ^fleet_id} = project -> project
      _none_or_another_fleets -> raise NotFoundError
    end
  end

  defp repository!(fleet_id, project) do
    {:ok, repository} = Code.repository(fleet_id, project)
    repository
  end

  # Each folder above the place shown, from the top, as a link.
  defp crumbs(_fleet_id, _repository, "", _at), do: []

  defp crumbs(fleet_id, repository, path, at) do
    names = String.split(path, "/")

    for depth <- 0..(length(names) - 2)//1 do
      above = names |> Enum.take(depth + 1) |> Enum.join("/")
      %{name: Enum.at(names, depth), link: Code.files_path(fleet_id, repository, above, at)}
    end
  end

  # A folder holds something: git keeps no empty folder. So a place that
  # holds nothing is a file, or nothing at all.
  defp listing(fleet_id, repository, path, at) do
    case Code.folder(repository, path, at) do
      {:ok, []} when path != "" ->
        file(repository, path, at)

      {:ok, entries} ->
        {:folder, Enum.map(entries, &entry_row(&1, fleet_id, repository, path, at))}

      {:error, error} ->
        unreadable_code(repository, error)
    end
  end

  # Each entry of a folder with its path from the top of the repository.
  defp entry_row(entry, fleet_id, repository, folder, at) do
    path = if folder == "", do: entry.name, else: folder <> "/" <> entry.name
    Map.merge(entry, %{path: path, link: Code.files_path(fleet_id, repository, path, at)})
  end

  defp file(repository, path, at) do
    case Code.file(repository, path, at) do
      {:ok, :too_large} -> {:file, :too_large}
      {:ok, bytes} -> {:file, if(Code.text?(bytes), do: bytes, else: :not_text)}
      :not_found -> raise NotFoundError
      {:error, error} -> unreadable_code(repository, error)
    end
  end

  defp unreadable_code(repository, error) do
    Logger.warning("The repository #{repository} could not be read: #{reason(error)}")
    :unreadable
  end

  # The tasks that produced each piece of evidence, by the evidence's id.
  defp producers(_fleet_id, [], _opts), do: %{}

  defp producers(fleet_id, evidence, opts) do
    fleet_id
    |> Graph.producers_of!(Enum.map(evidence, & &1.id), opts)
    |> Enum.group_by(& &1.target, & &1.source)
  end

  # The first read of the workspace a page makes is the one that finds out
  # whether the reader is one of the fleet's members.
  defp members_read(_fleet, {:ok, result}), do: {:ok, result}
  defp members_read(fleet, {:error, %Ash.Error.Forbidden{}}), do: {:members_only, fleet.name}
  defp members_read(_fleet, {:error, %Ash.Error.Invalid{}}), do: raise(NotFoundError)
  defp members_read(_fleet, {:error, failure}), do: raise(failure)

  # An item page's links and history are paged apart: moving one keeps where
  # the other stands.
  defp item_query(params, name, position) do
    %{"links" => params["links"], "history" => params["history"]}
    |> Map.put(name, position)
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Enum.sort()
  end

  defp fleet(fleet_id, opts) do
    case Fleets.get_fleet!(fleet_id, opts) do
      nil -> {:missing, nil}
      fleet -> {:ok, fleet}
    end
  end

  # A workspace is readable once its log has started being copied.
  defp ready(fleet, opts) do
    case Graph.get_cursor!(fleet.id, opts) do
      nil -> {:missing, fleet.name}
      cursor -> {:ready, cursor}
    end
  end

  defp seen(cursor), do: {cursor.run_id, cursor.applied_seq}

  defp filter!(params, shown) do
    view = view!(params)

    %{
      view: view,
      project: shown && shown.name,
      type: type!(params["type"]),
      owner: owner!(view, params["owner"]),
      goal: goal!(view, params["goal"]),
      archived?: archived!(params["archived"]),
      arrange: arrange!(view == :graph, params["arrange"]),
      every: every!(view == :graph, params["every"])
    }
  end

  # The Docs place shows its notebooks on a canvas, or as a list.
  defp docs!(params) do
    view =
      case params["view"] do
        nil -> :canvas
        "list" -> :list
        _unknown -> raise NotFoundError
      end

    %{
      view: view,
      arrange: arrange!(view == :canvas, params["arrange"]),
      every: every!(view == :canvas, params["every"])
    }
  end

  # Only a canvas is arranged.
  defp arrange!(_canvas?, nil), do: :time
  defp arrange!(true, arrange), do: Map.get(@arranges, arrange) || raise(NotFoundError)
  defp arrange!(false, _arrange), do: raise(NotFoundError)

  defp every!(_canvas?, nil), do: :day
  defp every!(true, "hour"), do: :hour
  defp every!(_canvas?, _every), do: raise(NotFoundError)

  # The graph is one picture, so it has no pages, and only it is drawn for
  # one Key.
  defp view!(%{"view" => "graph"} = params),
    do: if(paged?(params), do: raise(NotFoundError), else: :graph)

  defp view!(%{"view" => _unknown}), do: raise(NotFoundError)
  defp view!(_board), do: :board

  defp type!(nil), do: nil
  defp type!(type) when type in @types, do: type
  defp type!(_unknown), do: raise(NotFoundError)

  defp owner!(_view, nil), do: nil
  defp owner!(:graph, owner) when is_binary(owner), do: token_id!(owner)
  defp owner!(_view, _unknown), do: raise(NotFoundError)

  # Only the graph is drawn around one goal.
  defp goal!(_view, nil), do: nil
  defp goal!(:graph, "goal#" <> _number = id), do: id
  defp goal!(_view, _unknown), do: raise(NotFoundError)

  defp archived!(nil), do: false
  defp archived!("shown"), do: true
  defp archived!(_unknown), do: raise(NotFoundError)

  defp token_id!(digits) do
    if String.match?(digits, ~r/\A[1-9][0-9]{0,17}\z/),
      do: String.to_integer(digits),
      else: raise(NotFoundError)
  end

  defp cards_page(fleet, filter, params, opts) do
    Graph.workspace_cards(
      fleet.id,
      %{project: filter.project, type: filter.type, include_archived?: filter.archived?},
      Keyword.put(opts, :page, card_position(params) ++ [limit: 24])
    )
  end

  defp card_position(%{"after" => keyset}) when is_binary(keyset), do: [after: keyset]
  defp card_position(%{"before" => keyset}) when is_binary(keyset), do: [before: keyset]
  defp card_position(params), do: if(paged?(params), do: raise(NotFoundError), else: [])

  defp paged?(params), do: Map.has_key?(params, "after") or Map.has_key?(params, "before")

  defp position!(params, name) do
    case params[name] do
      nil -> []
      keyset when is_binary(keyset) -> [after: keyset]
      _unknown -> raise NotFoundError
    end
  end

  # An item's history is paged by the place in the log it reads back from.
  defp history_position!(params) do
    case params["history"] do
      nil ->
        %{}

      through when is_binary(through) ->
        if String.match?(through, ~r/\A(0|[1-9][0-9]{0,18})\z/),
          do: %{through_seq: String.to_integer(through)},
          else: raise(NotFoundError)

      _unknown ->
        raise NotFoundError
    end
  end

  defp page!({:ok, page}), do: page
  defp page!({:error, %Ash.Error.Invalid{}}), do: raise(NotFoundError)
  defp page!({:error, failure}), do: raise(failure)

  # A page reached by going forward always has one before it, and one reached
  # by going back always has one after it.
  defp page_links(%Ash.Page.Keyset{results: []}, _params, _path),
    do: %{previous: nil, next: nil}

  defp page_links(%Ash.Page.Keyset{results: results, more?: more?}, params, path) do
    {previous?, next?} =
      case params do
        %{"after" => _keyset} -> {true, more?}
        %{"before" => _keyset} -> {more?, true}
        _first_page -> {false, more?}
      end

    %{
      previous: if(previous?, do: path.(before: hd(results).__metadata__.keyset)),
      next: if(next?, do: path.(after: List.last(results).__metadata__.keyset))
    }
  end

  defp titles(_fleet_id, [], _opts), do: %{}

  defp titles(fleet_id, ids, opts) do
    fleet_id
    |> Graph.object_titles!(Enum.uniq(ids), opts)
    |> Map.new(&{&1.id, &1})
  end

  # Goals are listed one line each; every other item is a card. In the whole
  # fleet's view each is labelled with its project's title.
  defp entry(object, %{type: "goal"}, _fleet_id, _agents, labels), do: goal_row(object, labels)

  defp entry(object, _filter, fleet_id, agents, labels),
    do: card(object, fleet_id, agents, labels)

  defp goal_row(object, labels) do
    %{
      id: object.id,
      title: object.title,
      project: labels[object.project],
      starting?: starting?(object.sys),
      archived?: archived?(object.sys),
      status: goal_standing(object.card["status"]),
      joined: length(joined(object.sys)),
      changed_on: time(object.changed_at)
    }
  end

  # What a goal's page shows of the work around it: its map, as the Graph
  # view draws it around the goal (`RegentsWeb.Keyfleet.WorkspaceGraph.tree/2`), and
  # of what the work around it cites (`Regents.Keyfleet.Graph.Object`,
  # `:around_goal`), the saved notebook results, the notebooks and the
  # commits of the fleet's code; beside them the goal's own place in the
  # code, the folder `goals/goal-N`, and the notebooks tagged `goal-N` in its
  # project's space. `code` and `notebooks` are `:unreadable` when the code
  # store or the notebook hub doesn't answer, and `notebooks` is nil for a
  # fleet without notebooks. `graph` is the same map in its project's Graph
  # view.
  defp goal_work(fleet_id, goal, opts) do
    objects = fleet_id |> Graph.goal_work!(goal.id, opts) |> Enum.take(@goal_items)
    name = String.replace(goal.id, "#", "-")
    folder = "goals/" <> name
    repository = repository!(fleet_id, goal.project)

    cited =
      for object <- objects,
          field <- @cites,
          uri <- [object.card[field]],
          is_binary(uri),
          do: {object, uri, source(uri, fleet_id)}

    {notebooks, unshown} =
      goal_notebooks(
        fleet_id,
        space!(fleet_id, goal.project),
        name,
        for({_object, uri, {:notebook, _open}} <- cited, uniq: true, do: notebook_in(uri))
      )

    # An archived goal's map holds the archived items around it, as the goal
    # itself is one.
    archived? = archived?(goal.sys)

    map =
      fleet_id
      |> Graph.workspace_graph!(%{goal: goal.id, archived: archived?}, opts)
      |> WorkspaceGraph.items(fleet_id, %{})

    %{
      map: WorkspaceGraph.tree(map, goal.id),
      more?: map.more_nodes?,
      graph:
        board_path(fleet_id, %{
          view: :graph,
          project: goal.project,
          type: nil,
          owner: nil,
          goal: goal.id,
          archived?: archived?,
          arrange: :time,
          every: :day
        }),
      results:
        for {object, uri, {:notebook_result, uri}} <- cited do
          %{
            id: object.id,
            type: object.type,
            title: object.title,
            uri: uri,
            changed_on: time(object.changed_at)
          }
        end
        |> Enum.uniq_by(& &1.uri),
      commits:
        for {object, _uri, {:commit, hash, path}} <- cited do
          %{
            id: object.id,
            type: object.type,
            title: object.title,
            hash: hash,
            path: path,
            changed_on: time(object.changed_at)
          }
        end
        |> Enum.uniq_by(& &1.hash),
      name: name,
      folder: %{path: folder, link: Code.files_path(fleet_id, repository, folder)},
      code: folder_entries(fleet_id, repository, folder),
      notebooks: since_run(notebooks, run_pages(fleet_id, readable(notebooks))),
      notebooks_unshown: unshown
    }
  end

  # The notebooks tagged with the goal's name, then the ones its work cites
  # that aren't tagged, with how many of those aren't shown.
  defp goal_notebooks(fleet_id, space, name, cited) do
    case notebooks(fleet_id, space, tag: name, limit: 50) do
      tagged when is_list(tagged) ->
        {found, unshown} = cited_notebooks(fleet_id, cited -- Enum.map(tagged, &{space, &1.id}))
        {tagged ++ found, unshown}

      none_or_unreadable ->
        {none_or_unreadable, 0}
    end
  end

  # The space and id of a cited notebook, from its address.
  defp notebook_in(uri) do
    ["", "projects", space, "notebooks", id] = String.split(URI.parse(uri).path, "/")
    {space, id}
  end

  # The most recently cited, each asked for by its id at once, however old,
  # all within one page wait. One in a space that isn't one of the fleet's
  # projects', or since deleted, is left out; one the hub doesn't answer in
  # time, and those past the first @cited_notebooks, are counted as not shown.
  defp cited_notebooks(_fleet_id, []), do: {[], 0}

  defp cited_notebooks(fleet_id, cited) do
    {:ok, spaces} = Notebooks.spaces(fleet_id)
    ours = MapSet.new(spaces, fn {_project, space} -> space end)
    {asked, rest} = cited |> Enum.filter(&(elem(&1, 0) in ours)) |> Enum.split(@cited_notebooks)

    answers =
      Task.async_stream(
        asked,
        fn {space, id} -> {space, HubClient.notebook(fleet_id, space, id)} end,
        max_concurrency: @cited_notebooks,
        timeout: Notebooks.config()[:page_timeout_ms],
        on_timeout: :kill_task
      )

    {found, unanswered} =
      Enum.reduce(answers, {[], 0}, fn
        {:ok, {_space, {:ok, %{"status" => "deleted"}}}}, acc ->
          acc

        {:ok, {_space, {:ok, nil}}}, acc ->
          acc

        {:ok, {space, {:ok, notebook}}}, {found, unanswered} ->
          {[notebook_row(fleet_id, space, notebook) | found], unanswered}

        {:ok, {_space, {:error, error}}}, {found, unanswered} ->
          Logger.warning("A notebook of #{fleet_id} could not be read: #{reason(error)}")
          {found, unanswered + 1}

        {:exit, :timeout}, {found, unanswered} ->
          Logger.warning("A notebook of #{fleet_id} could not be read: timeout")
          {found, unanswered + 1}
      end)

    {Enum.reverse(found), unanswered + length(rest)}
  end

  defp folder_entries(fleet_id, repository, folder) do
    case Code.folder(repository, folder) do
      {:ok, entries} -> Enum.map(entries, &entry_row(&1, fleet_id, repository, folder, nil))
      {:error, error} -> unreadable_code(repository, error)
    end
  end

  # A space's notebooks as `query` narrows them (`HubClient.notebooks/3`),
  # newest first, each with its folder, when it was added and the link that
  # opens it: nil for a fleet without notebooks (`space!/2` false), none
  # before the project's space is made, and `:unreadable` when the hub
  # doesn't answer.
  defp notebooks(_fleet_id, false, _query), do: nil
  defp notebooks(_fleet_id, nil, _query), do: []

  defp notebooks(fleet_id, space, query) do
    case HubClient.notebooks(fleet_id, space, query) do
      {:ok, notebooks} ->
        Enum.map(notebooks, &notebook_row(fleet_id, space, &1))

      {:error, error} ->
        Logger.warning("The notebooks of #{fleet_id} could not be read: #{reason(error)}")
        :unreadable
    end
  end

  # A notebook as a page shows it: when it last changed (`changed`) as the
  # hub writes it, and the address tasks cite it by (`url`).
  defp notebook_row(fleet_id, space, notebook) do
    {:ok, added, _offset} = DateTime.from_iso8601(notebook["created_at"])

    %{
      id: notebook["id"],
      title: notebook["title"],
      author: notebook["author"],
      description: notebook["description"],
      folder: Enum.find_value(notebook["tags"], &folder/1),
      added: added,
      changed: notebook["updated_at"],
      open: notebook_link(fleet_id, space, notebook["id"]),
      url: Notebooks.notebook_url(fleet_id, space, notebook["id"])
    }
  end

  # The newest page Keyfleet keeps of a background run of each of `rows`'
  # notebooks, whoever started it, by notebook, from one read of Keyfleet's
  # own copies (`Regents.Keyfleet.Notebooks.SavedOutput`, which only the site itself
  # reads); none without a row.
  defp run_pages(_fleet_id, []), do: %{}

  defp run_pages(fleet_id, rows) do
    fleet_id
    |> Notebooks.newest_run_outputs!(Enum.map(rows, & &1.id), actor: %System{})
    |> Map.new(&{&1.notebook_id, &1})
  end

  # Each row with whether its notebook changed after its newest kept run page
  # was made (`changed_since_run?`, `Regents.Keyfleet.Notebooks.changed_since?/2`),
  # false while none is kept, as an agent's listing says it.
  defp since_run(rows, pages) when is_list(rows) do
    for row <- rows do
      Map.put(row, :changed_since_run?, changed_since_run?(row.changed, pages[row.id]))
    end
  end

  defp since_run(none_or_unreadable, _pages), do: none_or_unreadable

  defp changed_since_run?(_changed, nil), do: false
  defp changed_since_run?(changed, page), do: Notebooks.changed_since?(changed, page)

  defp folder("folder/" <> folder), do: folder
  defp folder(_tag), do: nil

  # Each notebook locked or open to every member's edits
  # (`Regents.Keyfleet.Notebooks.locks/1`), and whether the member is its creator:
  # its author, or the Key whose scratchpad it is.
  defp with_locks(rows, fleet_id, true, actor) when is_list(rows) do
    locks = Notebooks.locks(fleet_id)
    {subject, key} = viewer(fleet_id, actor)

    for row <- rows do
      lock = Map.get(locks, row.id, %{locked: true, key: nil})

      Map.merge(row, %{
        locked: lock.locked,
        creator?: if(lock.key, do: lock.key == key, else: row.author == subject)
      })
    end
  end

  defp with_locks(rows, _fleet_id, _hub?, _actor), do: rows

  defp viewer(fleet_id, %Human{} = actor) do
    {Notebooks.subject(actor), Keys.identity(actor, fleet_id)[:token_id]}
  end

  defp viewer(_fleet_id, _actor), do: {nil, nil}

  # The project's daily copies the member may bring back, each notebook's
  # newest first; none for anyone who holds no Key, or when they can't be
  # read now.
  defp copies(fleet_id, %Human{} = actor, project) do
    case Notebooks.copies(fleet_id, actor, Notebooks.subject(actor), project) do
      {:ok, notebooks} ->
        for notebook <- notebooks,
            copies = Enum.filter(notebook.copies, & &1.restorable),
            copies != [],
            do: %{notebook | copies: copies}

      {:error, _reason} ->
        []
    end
  end

  defp copies(_fleet_id, _actor, _project), do: []

  # A project's space in the fleet's notebook hub: false for a fleet without
  # notebooks, nil before it is made.
  defp space!(fleet_id, project) do
    with true <- Notebooks.hub?(fleet_id),
         {:ok, space} <- Notebooks.space(fleet_id, project) do
      space
    else
      false -> false
      {:error, error} -> raise error
    end
  end

  defp notebook_link(fleet_id, space, notebook_id),
    do: notebook_open(fleet_id, Notebooks.notebook_path(space, notebook_id))

  defp notebook_open(fleet_id, to),
    do: "/keyfleet/fleets/#{fleet_id}/notebooks/open?" <> URI.encode_query(to: to)

  # Only the kind of failure is logged: a database error carries its query.
  defp reason(%module{}), do: inspect(module)
  defp reason(reason), do: inspect(reason)

  defp card(object, fleet_id, agents, labels) do
    %{
      id: object.id,
      type: object.type,
      title: object.title,
      project: labels[object.project],
      archived?: archived?(object.sys),
      starting?: starting?(object.sys),
      by: created_by(object.sys, agents),
      changed_at: time(object.changed_at),
      facts:
        facts(object.type, Map.put(object.card, "review", object.review), fleet_id) ++
          joined_fact(object.sys),
      gist: object.card["gist"]
    }
  end

  defp facts("goal", card, _fleet_id),
    do: present([{"Status", choice("status", card["status"])}])

  defp facts("task", card, _fleet_id) do
    present([
      {"Progress", choice("progress", card["progress"])},
      {"Review", card["review"] && choice("review", card["review"])}
    ])
  end

  defp facts("finding", card, _fleet_id),
    do: present([{"Confidence", choice("confidence", card["confidence"])}])

  defp facts("evidence", card, fleet_id),
    do: present([{"Source", source(card["source_uri"], fleet_id)}])

  defp facts("service", card, _fleet_id) do
    price =
      case {card["price_proposal"], card["payment_asset"]} do
        {nil, _asset} -> nil
        {price, nil} -> price
        {price, "FLEET_TOKEN"} -> "#{price} in the fleet’s own token"
        {price, asset} -> "#{price} #{asset}"
      end

    present([{"Customer", card["customer"]}, {"Proposed price", price}])
  end

  defp facts(_type, _card, _fleet_id), do: []

  defp present(facts), do: Enum.reject(facts, &is_nil(elem(&1, 1)))

  defp detail(object, fleet_id, agents, opts) do
    known = Map.get(@fields, object.type, [])
    shown = MapSet.new(["title", "discussion" | Enum.map(known, &elem(&1, 0))])

    others =
      object.data
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(shown, &1))
      |> Enum.sort()
      |> Enum.map(&{&1, humanize(&1)})

    %{
      id: object.id,
      type: object.type,
      title: object.data["title"],
      archived?: archived?(object.sys),
      starting?: starting?(object.sys),
      by: created_by(object.sys, agents),
      version: object.version,
      changed_at: time(object.changed_at),
      fields:
        receipt(object, fleet_id) ++
          Enum.flat_map(known ++ others, fn {field, label} ->
            case field_value(field, object.data[field], fleet_id) do
              nil -> []
              shown -> [{label, shown}]
            end
          end) ++ rerun_check(object) ++ joined_field(object.sys, agents),
      discussion: discussion(object.data["discussion"], fleet_id, opts)
    }
  end

  # Where a submitted task's review stands, and what a review judged: the
  # task's version and who submitted it.
  defp receipt(%{type: "task", review: review}, _fleet_id) when is_binary(review),
    do: [{"Review", choice("review", review)}]

  defp receipt(%{type: "review", sys: %{"review" => review}}, fleet_id) do
    present([
      {"Version reviewed", Integer.to_string(review["task_version"])},
      {"Commit reviewed", source(review["commit_ref"], fleet_id)},
      {"Submitted by", {:key, review["submitted_by"]["key"]["token_id"], nil}}
    ])
  end

  defp receipt(_object, _fleet_id), do: []

  # Once a task names its commit or its rerun, whether it carries everything
  # a rerun needs, or each thing it still needs.
  defp rerun_check(%{type: "task", data: data}) do
    if data["commit_ref"] || data["rerun"],
      do: [{"Rerun check", rerun_needs(RerunCheck.missing(data))}],
      else: []
  end

  defp rerun_check(_object), do: []

  defp rerun_needs([]), do: "Complete"
  defp rerun_needs(missing), do: {:list, Enum.map(missing, &("Needs " <> &1.need))}

  defp field_value(_field, nil, _fleet_id), do: nil
  defp field_value(_field, [], _fleet_id), do: nil

  defp field_value(field, uri, fleet_id)
       when field in ["source_uri", "result_ref", "commit_ref", "notebook_ref"],
       do: source(uri, fleet_id)

  defp field_value(field, value, _fleet_id) when is_map_key(@choices, field),
    do: choice(field, value)

  # How to run a task's work again, a line each: the command, then its
  # lockfile, inputs and outputs, each with its role and digest.
  defp field_value("rerun", %{"command" => command} = rerun, _fleet_id) do
    files =
      [
        {"Lockfile", List.wrap(rerun["lockfile"])},
        {"Input", rerun["inputs"]},
        {"Output", rerun["outputs"]}
      ]
      |> Enum.flat_map(fn {label, files} -> Enum.map(files, &rerun_file(label, &1)) end)

    {:list, [command | files]}
  end

  defp field_value(_field, value, _fleet_id), do: value(value)

  defp rerun_file(label, file) do
    details = Enum.reject([file["role"], file["digest"]], &is_nil/1)
    Enum.join(["#{label}: #{file["path"]}" | details], " · ")
  end

  # A commit of one of the fleet's own repositories is shown as that commit,
  # opened on this site; a saved result of one of the fleet's notebooks as that result; one
  # of its notebooks as that notebook, opened through this site; any other
  # address as `value/1` shows it.
  defp source(nil, _fleet_id), do: nil

  defp source(uri, fleet_id) do
    case fleet_commit(uri, fleet_id) do
      {repository, hash} -> {:commit, hash, Code.commit_path(fleet_id, repository, hash)}
      nil -> notebook_source(uri, fleet_id)
    end
  end

  defp notebook_source(uri, fleet_id) do
    saved = String.replace_prefix(uri, Notebooks.url(fleet_id, "/results/"), "")
    path = String.replace_prefix(uri, Notebooks.url(fleet_id, ""), "")

    cond do
      saved != uri and Regex.match?(@saved_result, saved) ->
        {:notebook_result, uri}

      path != uri and Notebooks.notebook?(path) ->
        {:notebook, notebook_open(fleet_id, path)}

      true ->
        value(uri)
    end
  end

  @doc """
  The repository and full hash a workspace's address of a commit names, as
  `{repository, hash}`, when it is a commit of one of the fleet's own
  repositories on this site (`commit_url/3`); nil for any other address.
  """
  def fleet_commit(uri, fleet_id) when is_binary(uri) do
    code = String.replace_prefix(uri, Endpoint.url() <> Fleets.path(fleet_id) <> "/code/", "")

    with true <- code != uri,
         [repository, "commits", hash] <- String.split(code, "/"),
         {:ok, ^fleet_id} <- Code.repository_fleet(repository),
         true <- Code.full_hash?(hash) do
      {repository, hash}
    else
      _other -> nil
    end
  end

  def fleet_commit(_uri, _fleet_id), do: nil

  # Text as written; an address with a scheme allowed for links is a link.
  defp value(value) when is_binary(value) do
    if link?(value), do: {:link, value}, else: value
  end

  defp value(values) when is_list(values), do: {:list, Enum.map(values, &value/1)}

  defp link?(value) do
    String.starts_with?(value, @link_schemes) and byte_size(value) <= 512 and
      not String.match?(value, ~r/[\s\x00-\x1f\x7f]/u)
  end

  @doc ~S|What a page calls one of a field's choices: `choice("progress", "doing")` is "In progress".|
  def choice(field, value), do: @choices |> Map.fetch!(field) |> Map.fetch!(value)

  defp discussion(links, fleet_id, opts) when is_list(links) and links != [] do
    rooms = fleet_id |> Rooms.list_rooms!(opts) |> Map.new(&{&1.slug, RoomsLive.room_label(&1)})

    for %{"room" => room, "seq" => seq} <- links, is_binary(room) and is_integer(seq) do
      name = rooms[room]

      %{
        room: name || room,
        seq: seq,
        path:
          if(name && Regex.match?(@room_slug, room),
            do: KeyLinks.room_path(fleet_id, room)
          )
      }
    end
  end

  defp discussion(_links, _fleet_id, _opts), do: []

  defp other_end(%{source: object_id, target: other}, object_id), do: other
  defp other_end(%{source: other}, _object_id), do: other

  defp link_row(relation, object, titles) do
    outgoing? = relation.source == object.id
    other = if outgoing?, do: relation.target, else: relation.source

    %{
      id: relation.id,
      outgoing?: outgoing?,
      relation: relation_words(relation.type),
      type_name: elem(type_name(object.type), 0),
      other: item_part(other, titles)
    }
  end

  @doc "What one item is to another by their link, read from its source to its target."
  def relation_words(type), do: Map.fetch!(@relations, type)

  # The ids a change's line names.
  defp mentions(%{brief: brief}),
    do:
      Enum.filter(
        [brief["object"], brief["source"], brief["target"], brief["task"]],
        &is_binary/1
      )

  defp line(event, titles, agents) do
    parts = event |> parts(titles) |> Enum.map(&named(&1, agents))
    %{seq: event.seq, at: time(event.timestamp), parts: parts}
  end

  # A review is told as its decision on the task, from its creation on the
  # board and from its link to the task in the task's history.
  defp parts(
         %{type: "object.created", brief: %{"object_type" => "review", "task" => task} = brief} =
           event,
         titles
       )
       when is_binary(task),
       do: reviewed(event, brief, task, titles)

  defp parts(
         %{
           type: "relation.created",
           brief: %{"relation_type" => "reviews", "target" => task} = brief
         } =
           event,
         titles
       )
       when is_binary(task),
       do: reviewed(event, brief, task, titles)

  defp parts(%{type: "object.created", brief: %{"object" => id} = brief} = event, titles)
       when is_binary(id) do
    {singular, _plural} = type_name(brief["object_type"])
    [who(event.actor), " added the #{singular} ", item_part(id, titles), "."]
  end

  defp parts(
         %{type: "patch.applied", brief: %{"object" => id, "archived" => true}} = event,
         titles
       )
       when is_binary(id),
       do: [who(event.actor), " archived ", item_part(id, titles), "."]

  # A member joining or leaving; the workspace's own rewrites of who joined
  # are told as updates.
  defp parts(
         %{
           type: "patch.applied",
           actor: "member:" <> _,
           brief: %{"object" => id, "joins" => joins}
         } = event,
         titles
       )
       when is_binary(id) and joins != 0,
       do: [
         who(event.actor),
         if(joins > 0, do: " joined ", else: " left "),
         item_part(id, titles),
         "."
       ]

  defp parts(
         %{type: "patch.applied", brief: %{"object" => id, "submitted" => true}} = event,
         titles
       )
       when is_binary(id),
       do: [who(event.actor), " submitted ", item_part(id, titles), " for review."]

  defp parts(%{type: "patch.applied", brief: %{"object" => id} = brief} = event, titles)
       when is_binary(id) do
    item = item_part(id, titles)
    type = titles[id] && titles[id].type

    case changes(brief, type) do
      [] -> [who(event.actor), " updated ", item, "."]
      changes -> [who(event.actor), " updated ", item, ": " | changes] ++ ["."]
    end
  end

  # A fork's link is told as the copy being made.
  defp parts(
         %{type: "relation.created", brief: %{"relation_type" => "forks", "target" => task}} =
           event,
         titles
       )
       when is_binary(task),
       do: [who(event.actor), " forked ", item_part(task, titles), "."]

  defp parts(
         %{type: type, brief: %{"source" => source, "target" => target} = brief} = event,
         titles
       )
       when type in ["relation.created", "relation.removed"] and is_binary(source) and
              is_binary(target) do
    words = relation_words(brief["relation_type"])

    {verb, joiner, clause} =
      if type == "relation.created",
        do: {" linked ", " to ", ", which it #{words}."},
        else: {" unlinked ", " from ", ", which it no longer #{words}."}

    [who(event.actor), verb, item_part(source, titles), joiner, item_part(target, titles), clause]
  end

  defp parts(%{type: "keyfleet.attention", brief: %{"kind" => kind, "object" => id}}, titles)
       when kind in ["task_unblocked", "needs_review"] do
    subject =
      case item_part(id, titles) do
        {:item, _id, nil} -> "An item"
        item -> item
      end

    [subject, if(kind == "task_unblocked", do: " is ready to start.", else: " needs review.")]
  end

  defp parts(%{type: "keyfleet.attention"}, _titles),
    do: ["Something in the workspace needs attention."]

  defp parts(_event, _titles), do: ["The workspace changed."]

  defp reviewed(event, brief, task, titles) do
    did = if brief["decision"] == "accept", do: " accepted ", else: " disputed "
    [who(event.actor), did, item_part(task, titles), "."]
  end

  # What a change changed, in the order the fields are shown, with the new
  # value of the few short fields.
  defp changes(brief, type) do
    order = @fields |> Map.get(type, []) |> Enum.map(&elem(&1, 0))
    values = brief["values"]

    brief["fields"]
    |> Enum.reject(&(&1 == "sys"))
    |> Enum.sort_by(&(Enum.find_index(order, fn field -> field == &1 end) || length(order)))
    |> Enum.map(&change(&1, field_label(type, &1), values[&1]))
    |> Enum.intersperse([", "])
    |> List.flatten()
  end

  defp change(field, label, %{"new" => new}) when is_binary(new),
    do: [String.downcase(label) <> " is now " <> String.downcase(choice(field, new))]

  defp change(_field, label, _value), do: [String.downcase(label)]

  defp field_label(type, field) do
    case List.keyfind(Map.get(@fields, type, []), field, 0) do
      {^field, label} -> label
      nil -> if field == "title", do: "Title", else: humanize(field)
    end
  end

  defp item_part(id, titles) do
    case titles[id] do
      nil -> {:item, id, nil}
      object -> {:item, id, object.title}
    end
  end

  # A member's change names the key it was made as, with the agent's wallet
  # when an agent wrote as it (`named/2` puts its name in); anything else was
  # the workspace's own doing.
  defp who(actor) do
    case Graph.Event.member(actor) do
      {token_id, kind, wallet} -> {:by, token_id, agent_wallet(kind, wallet)}
      nil -> "Keyfleet"
    end
  end

  defp named({:by, token_id, wallet}, agents), do: {:key, token_id, agents[wallet]}
  defp named(part, _agents), do: part

  @doc """
  The key an item was added as, with the name of the agent that added it
  (`agent_names/1` of `creator_wallet/1`); Keyfleet added the starting goals.
  """
  def created_by(%{"created_by" => %{"key" => %{"token_id" => token_id}}} = sys, agents),
    do: {:key, token_id, agents[creator_wallet(sys)]}

  def created_by(%{"created_by" => nil}, _agents), do: "Keyfleet"

  @doc "The wallet of the agent that added an item, or nil when no agent did."
  def creator_wallet(%{"created_by" => nil}), do: nil
  def creator_wallet(%{"created_by" => by}), do: agent_wallet(by["kind"], by["wallet"])

  # Who joined a goal or task, in the order they joined, each told as the
  # key it joined as with the name of its agent.
  defp joined(sys), do: Map.get(sys, "joined", [])

  defp joined_wallets(sys), do: Enum.map(joined(sys), &agent_wallet(&1["kind"], &1["wallet"]))

  defp joined_field(sys, agents) do
    case joined(sys) do
      [] ->
        []

      members ->
        keys =
          for member <- members,
              do:
                {:key, member["key"]["token_id"],
                 agents[agent_wallet(member["kind"], member["wallet"])]}

        [{"Joined", {:list, keys}}]
    end
  end

  defp joined_fact(sys) do
    case length(joined(sys)) do
      0 -> []
      count -> [{"Joined", Integer.to_string(count)}]
    end
  end

  defp actor_wallet(event) do
    case who(event.actor) do
      {:by, _token_id, wallet} -> wallet
      "Keyfleet" -> nil
    end
  end

  defp agent_wallet("agent", wallet), do: wallet
  defp agent_wallet(_kind, _wallet), do: nil

  @doc """
  The names agents gave themselves, by wallet, looked up together for a
  page. A person, or an agent that has no profile here, has no name.
  Agents choose their own names, so none can hide or reverse the Key beside it.
  """
  def agent_names(wallets) do
    wallets
    |> Agents.names_by_wallet()
    |> Map.new(fn {wallet, name} -> {wallet, DirectoryMD.visible(name)} end)
  end

  defp archived?(sys), do: sys["archived"] == true

  defp starting?(sys), do: is_integer(sys["starting"])

  # A push an agent sent names the agent beside its Key.
  defp pushes(pushes, fleet_id, repository) do
    agents = agent_names(Enum.map(pushes, & &1.acting_agent_wallet))
    Enum.map(pushes, &push(&1, fleet_id, repository, agents))
  end

  # The log stamps every event in UTC.
  defp push(push, fleet_id, repository, agents) do
    %{
      id: push.id,
      token_id: push.token_id,
      agent: agents[push.acting_agent_wallet],
      what: moved(push.ref),
      commit: {:commit, push.head, Code.commit_path(fleet_id, repository, push.head)},
      at: push.pushed_at
    }
  end

  defp moved("refs/heads/" <> branch), do: "changes to " <> branch
  defp moved("refs/tags/" <> tag), do: "the tag " <> tag
  defp moved(ref), do: ref

  defp time(timestamp) do
    {:ok, datetime, 0} = DateTime.from_iso8601(timestamp)
    datetime
  end

  defp humanize(field), do: field |> String.replace("_", " ") |> String.capitalize()
end
