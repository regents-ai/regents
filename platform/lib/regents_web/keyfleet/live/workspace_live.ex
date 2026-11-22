defmodule RegentsWeb.Keyfleet.WorkspaceLive do
  @moduledoc """
  A fleet's workspace, for people to read: the goals, tasks, findings,
  evidence, services, notes and dead ends its key holders'
  agents keep, what each one is linked to, and everything that changed.

  It has four places, each one address: the Project (goals, tasks and what
  changed), its Docs (the fleet's notebooks), its Code and Public (what the
  fleet's Keys made public, which anyone reads), in one of the fleet's
  projects or across all of them, as the project picker chooses.
  The only writes are pins, a notebook or a piece of code a member keeps at
  hand for every member (`Regents.Keyfleet.Graph.Pin`); starting, archiving,
  taking over and deleting a project as the member's Key
  (`Regents.Keyfleet.Projects`); making posts public as that Key and taking them
  back (`Regents.Keyfleet.Projects.Publication`); and the buttons that open the
  notebooks or make a git password. Everything shown is what `RegentsWeb.Keyfleet.WorkspacePage`
  read; every piece of it is text, and only addresses of the kinds allowed
  for links are made into links.
  """

  use RegentsWeb, :html

  import RegentsWeb.Keyfleet.Components.AgentPicture
  import RegentsWeb.Keyfleet.Components.LoadFailed

  alias Ash.Error.Action.InvalidArgument
  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Fleets.Rules
  alias Regents.Keyfleet.{Graph, Keys, Notebooks, Projects}
  alias Regents.Keyfleet.Graph.Errors.{EditsRestrictedError, NotKeyHolderError}
  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError
  alias Regents.Keyfleet.Projects.Errors.{ClosedError, HoldError, NameTakenError, PublishError}
  alias RegentsWeb.Keyfleet.ActivityLines
  alias RegentsWeb.Keyfleet.BoxLimit
  alias RegentsWeb.Keyfleet.Components.Shell
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.PageRead
  alias RegentsWeb.Keyfleet.ProjectPage
  alias RegentsWeb.Keyfleet.RoomsLive
  alias RegentsWeb.Keyfleet.ShellLive
  alias RegentsWeb.Keyfleet.WorkspacePage

  # How long a workspace page waits after a notice of changes before it reads
  # them, so a burst of writes is read once.
  @workspace_refresh_after 1_000

  @pin_places %{"docs" => :docs, "code" => :code}

  attr :board, :any, required: true, doc: "the workspace as read, or `:unreadable`"
  attr :notebooks_notice, :string, default: nil
  attr :code_password, :map, default: nil, doc: "the git password just made, and until when"
  attr :code_notice, :string, default: nil
  attr :project_notice, :string, default: nil, doc: "why a project press was refused"
  attr :publish_notice, :string, default: nil, doc: "why making posts public was refused"

  attr :signed_out?, :boolean,
    default: false,
    doc: "whether nobody is signed in, so the members-only page offers Sign in"

  # The board and an item are drawn inside the fleet's page, under its name
  # and bar (`RegentsWeb.Keyfleet.FleetLive`).
  def board(%{board: :unreadable} = assigns), do: ~H|<.unreadable id="workspace-page" />|

  def board(%{board: %{members_only?: true}} = assigns),
    do: ~H|<.members_only id="workspace-page" fleet={@board} signed_out?={@signed_out?} />|

  def board(assigns) do
    ~H"""
    <article
      id="workspace-page"
      class="workspace-page"
      phx-hook="MotionTabs"
      data-active={@board.place}
      data-variant={RegentsWeb.Motion.standard("tabs")}
    >
      <.places fleet_id={@board.fleet_id} place={@board.place} project={@board.project} />
      <.projects
        board={@board}
        notice={@project_notice}
      />
      <.public_notice place={@board.place} />

      <div
        id={"workspace-place-#{@board.place}"}
        class="workspace-place"
        role="tabpanel"
        aria-labelledby={"workspace-tab-#{@board.place}"}
      >
        <.project :if={@board.place == :project} board={@board} />
        <.docs :if={@board.place == :docs} board={@board} notice={@notebooks_notice} />
        <.code
          :if={@board.place == :code}
          board={@board}
          password={@code_password}
          notice={@code_notice}
        />
        <.public :if={@board.place == :public} board={@board} notice={@publish_notice} />
      </div>
    </article>
    """
  end

  attr :fleet_id, :string, required: true
  attr :place, :atom, required: true
  attr :project, :string, default: nil

  # The four places, one tab each named with the tool it runs on or, for
  # Public, who reads it, above a chart that rises over the one open. The
  # chart only decorates.
  defp places(assigns) do
    ~H"""
    <nav id="workspace-places" class="workspace-places" aria-labelledby="workspace-places-title">
      <h2 id="workspace-places-title" class="visually-hidden">Workspace</h2>
      <div
        id="workspace-places-chart"
        class="workspace-places-chart"
        phx-hook="PlacesChart"
        phx-mounted={JS.ignore_attributes(["data-chart-ready"])}
        data-place={@place}
        aria-hidden="true"
      >
        <canvas id="workspace-places-canvas" data-chart-canvas phx-update="ignore"></canvas>
      </div>
      <div class="workspace-places-list" role="tablist" aria-labelledby="workspace-places-title">
        <.link
          :for={place <- WorkspacePage.places()}
          id={"workspace-tab-#{place}"}
          class="rg-panel workspace-place-tab"
          role="tab"
          data-tab={place}
          aria-selected={to_string(place == @place)}
          aria-controls={place == @place && "workspace-place-#{place}"}
          patch={WorkspacePage.place_path(@fleet_id, place, @project)}
        >
          <span class="workspace-place-name">{place_name(place)}</span>
          <span class="workspace-place-tool">{place_tool(place)}</span>
        </.link>
        <span
          class="workspace-places-ink"
          data-ink
          aria-hidden="true"
          phx-mounted={JS.ignore_attributes(["style"])}
        ></span>
      </div>
    </nav>
    """
  end

  attr :board, :map, required: true
  attr :notice, :string, default: nil

  # The picker: All projects, then the active projects, then the archived
  # ones, each with the Key that holds it. Beside it what the member's Key
  # may do now: start a project when it has none active, archive its active
  # one, take over the archived project on show, or delete it when the Key
  # started it; taking one over never lets a Key delete it. Delete asks first.
  # The Key holding the project on show also chooses who sees its page's work
  # and the line its page describes it with.
  defp projects(assigns) do
    on_show = Enum.find(assigns.board.projects, &(&1.name == assigns.board.project))

    assigns =
      assign(assigns,
        active: Enum.filter(assigns.board.projects, &(&1.state == :active)),
        archived: Enum.filter(assigns.board.projects, &(&1.state == :archived)),
        on_show: on_show,
        deletable?: deletable?(on_show, assigns.board.you)
      )

    ~H"""
    <section id="workspace-projects" class="workspace-projects" aria-label="Projects">
      <nav id="workspace-project-picker" class="workspace-project-picker" aria-label="Projects">
        <.link
          id="workspace-project-all"
          patch={picker_path(@board, nil)}
          aria-current={if is_nil(@board.project), do: "page"}
        >
          All projects
        </.link>
        <.project_link :for={project <- @active} board={@board} project={project} />
      </nav>
      <div :if={@archived != []} id="workspace-project-archive" class="workspace-project-archive">
        <h3>Archived</h3>
        <nav class="workspace-project-picker" aria-label="Archived projects">
          <.project_link :for={project <- @archived} board={@board} project={project} />
        </nav>
      </div>
      <div :if={@board.you} id="workspace-project-actions" class="workspace-project-actions">
        <Regent.Primitives.disclosure
          :if={is_nil(@board.you.active)}
          id="project-start"
          summary="New project"
        >
          <form id="project-start-form" class="workspace-project-form" phx-submit="project_start">
            <label>
              Title <input name="title" type="text" maxlength="60" required />
            </label>
            <label>
              Short name
              <input
                name="name"
                type="text"
                maxlength="32"
                pattern="[a-z0-9]+(-[a-z0-9]+)*"
                title="Lowercase letters, digits and hyphens"
                required
              />
            </label>
            <Regent.Primitives.button type="submit">
              Start as {ActivityLines.key_name(@board.you.key, nil)}
            </Regent.Primitives.button>
          </form>
        </Regent.Primitives.disclosure>
        <Regent.Primitives.button
          :if={@board.you.active}
          id="project-archive"
          variant="secondary"
          phx-click="project_archive"
        >
          Archive {title(@board.projects, @board.you.active)}
        </Regent.Primitives.button>
        <Regent.Primitives.button
          :if={@on_show && @on_show.state == :archived && is_nil(@board.you.active)}
          id="project-take-over"
          variant="secondary"
          phx-click="project_take_over"
          phx-value-project={@on_show.name}
        >
          Take over {@on_show.title}
        </Regent.Primitives.button>
        <Regent.Primitives.button
          :if={@deletable?}
          id="project-delete"
          variant="secondary"
          phx-click="project_delete"
          phx-value-project={@on_show.name}
          data-confirm={"Delete #{@on_show.title} for good? Its work, notebooks and code go with it."}
          data-confirm-action="Delete"
        >
          Delete {@on_show.title}
        </Regent.Primitives.button>
        <Regent.Primitives.button
          :if={@on_show && @on_show.key == @board.you.key}
          id="project-show"
          variant="secondary"
          phx-click="project_show"
          phx-value-project={@on_show.name}
          phx-value-shown={to_string(not @on_show.shown_to_everyone)}
        >
          {if @on_show.shown_to_everyone,
            do: "Show its page’s work to members only",
            else: "Show its page’s work to everyone"}
        </Regent.Primitives.button>
        <Regent.Primitives.disclosure
          :if={@on_show && @on_show.key == @board.you.key}
          id="project-describe"
          summary="Description"
        >
          <form
            id="project-describe-form"
            class="workspace-project-form"
            phx-submit="project_describe"
          >
            <input type="hidden" name="project" value={@on_show.name} />
            <label>
              Description
              <input
                name="description"
                type="text"
                maxlength="160"
                value={@on_show.description}
              />
            </label>
            <Regent.Primitives.button type="submit">Save description</Regent.Primitives.button>
          </form>
        </Regent.Primitives.disclosure>
      </div>
      <p :if={@on_show} id="project-page-link">
        <.link navigate={ProjectPage.path(@board.fleet_id, @on_show.name)}>
          {@on_show.title}’s page
        </.link>
        · {if @on_show.shown_to_everyone,
          do: "shows its work to everyone",
          else: "shows its work to members"}
      </p>
      <p :if={@notice} id="project-notice" class="workspace-notebooks-notice" role="status">
        {@notice}
      </p>
    </section>
    """
  end

  # An archived project the member's Key started, whichever Key holds it. No
  # Key started General, so it never shows Delete.
  defp deletable?(%{state: :archived, created_by_key: key}, %{key: key}), do: true
  defp deletable?(_on_show, _you), do: false

  attr :board, :map, required: true
  attr :project, :map, required: true

  defp project_link(assigns) do
    ~H"""
    <.link
      id={"workspace-project-#{@project.name}"}
      data-project={@project.name}
      patch={picker_path(@board, @project.name)}
      aria-current={if @board.project == @project.name, do: "page"}
    >
      {@project.title} · {holder(@project.key)}
    </.link>
    """
  end

  defp title(projects, name), do: Enum.find_value(projects, &(&1.name == name && &1.title))

  # The picker keeps the Project's graph open while it is, and the Docs
  # shown as they are.
  defp picker_path(%{place: :project, filter: %{view: :graph}} = board, project),
    do: WorkspacePage.board_path(board.fleet_id, %{graph_filter(board.filter) | project: project})

  defp picker_path(%{place: :docs, docs: docs} = board, project),
    do: WorkspacePage.docs_path(board.fleet_id, project, docs)

  defp picker_path(board, project),
    do: WorkspacePage.place_path(board.fleet_id, board.place, project)

  defp graph_filter(filter),
    do: %{filter | view: :graph, type: nil, owner: nil, goal: nil, archived?: false}

  # Who holds a project: one Key, or the whole fleet for a shared one.
  defp holder(nil), do: "Shared"
  defp holder(key), do: ActivityLines.key_name(key, nil)

  defp place_name(:project), do: "Project"
  defp place_name(:docs), do: "Docs"
  defp place_name(:code), do: "Code"
  defp place_name(:public), do: "Public"

  defp place_tool(:project), do: "ActiveGraph"
  defp place_tool(:docs), do: "marimo"
  defp place_tool(:code), do: "Git"
  defp place_tool(:public), do: "Open to all"

  attr :board, :map, required: true

  # The Project as a board, or as a graph of its items and their links, under
  # how many of its goals and tasks stand where.
  defp project(assigns) do
    ~H"""
    <.counts :if={@board.ready?} counts={@board.counts} />

    <nav id="workspace-views" class="workspace-views" aria-label="Project views">
      <.link
        :for={{view, label} <- [board: "Board", graph: "Graph"]}
        id={"workspace-view-#{view}"}
        class="rg-panel"
        patch={view_path(@board, view)}
        aria-current={if @board.filter.view == view, do: "page"}
      >
        {label}
      </.link>
    </nav>

    <.unavailable :if={not @board.ready?} />
    <.board_view :if={@board.ready? and @board.filter.view == :board} board={@board} />
    <.graph_view :if={@board.ready? and @board.filter.view == :graph} board={@board} />
    """
  end

  attr :counts, :map, required: true

  # One line of numbers, each in the colour of where it stands as the graph
  # draws it; a number rolls to its new value when the work moves.
  defp counts(assigns) do
    ~H"""
    <dl id="workspace-counts" class="workspace-counts">
      <div :for={{standing, label, tone} <- counted()} data-standing={standing} data-tone={tone}>
        <dt>{label}</dt>
        <dd>
          <span
            id={"workspace-count-#{standing}"}
            phx-hook="MotionCount"
            data-variant={RegentsWeb.Motion.standard("count")}
          ><span data-count>{Rules.grouped(@counts[standing])}</span></span>
        </dd>
      </div>
    </dl>
    """
  end

  defp counted do
    [
      {:open_goals, "Open goals", "open"},
      {:open_tasks, "Open tasks", "open"},
      {:working, "In progress", "doing"},
      {:waiting_review, "Awaiting review", "waiting"},
      {:blocked, "Blocked", "held"},
      {:accepted, "Accepted", "done"}
    ]
  end

  # Switching keeps the kind of item shown, and the archived ones.
  defp view_path(board, :board),
    do:
      WorkspacePage.board_path(board.fleet_id, %{
        board.filter
        | view: :board,
          owner: nil,
          goal: nil
      })

  defp view_path(board, :graph),
    do: WorkspacePage.board_path(board.fleet_id, %{board.filter | view: :graph})

  attr :board, :map, required: true

  # The fleet's goals, its workstream and its items, with how work moves
  # between Keys beside them.
  defp board_view(assigns) do
    ~H"""
    <div class="workspace-grid">
      <div class="workspace-main">
        <section
          id="workspace-goals"
          class="workspace-panel workspace-items"
          aria-labelledby="workspace-goals-title"
        >
          <h2 id="workspace-goals-title">Goals</h2>
          <p class="workspace-detail">Ask your agent to join one, or to add its own.</p>
          <.goal_rows id="workspace-goal-rows" rows={@board.goals} fleet_id={@board.fleet_id} />
          <.link id="workspace-all-goals" class="workspace-toggle" patch={@board.all_goals}>
            See every goal
          </.link>
        </section>

        <section
          id="workspace-reviews"
          class="workspace-panel workspace-activity"
          aria-labelledby="workspace-reviews-title"
        >
          <h2 id="workspace-reviews-title">Reviews</h2>
          <p :if={@board.reviews == []} class="workspace-detail">Nothing awaits review.</p>
          <p :if={@board.reviews != []} class="workspace-detail">
            Submitted work awaiting review, the longest wait first.
          </p>
          <.feed :let={task} id="workspace-review-rows" rows={@board.reviews} key={:id}>
            <p><.link patch={task.path}>{task.title}</.link></p>
          </.feed>
        </section>

        <section
          class="workspace-panel workspace-activity"
          aria-labelledby="workspace-activity-title"
        >
          <h2 id="workspace-activity-title">Workstream</h2>
          <.feed :let={line} id="workspace-activity" rows={@board.activity} key={:seq}>
            <p><.line parts={line.parts} fleet_id={@board.fleet_id} /></p>
            <p :if={line.note} class="workspace-text">{line.note}</p>
          </.feed>
        </section>

        <section class="workspace-panel workspace-items" aria-labelledby="workspace-items-title">
          <h2 id="workspace-items-title">Items</h2>

          <nav class="workspace-filters" aria-label="Kinds of item">
            <.link
              :for={{type, label} <- [{nil, "Everything"} | kinds()]}
              patch={WorkspacePage.board_path(@board.fleet_id, %{@board.filter | type: type})}
              aria-current={if @board.filter.type == type, do: "page"}
              data-type-filter={type || "all"}
            >
              {label}
            </.link>
          </nav>

          <.link
            id="workspace-archived-toggle"
            class="workspace-toggle"
            patch={
              WorkspacePage.board_path(@board.fleet_id, %{
                @board.filter
                | archived?: not @board.filter.archived?
              })
            }
          >
            {if @board.filter.archived?, do: "Hide archived items", else: "Show archived items"}
          </.link>

          <.no_cards
            :if={@board.cards == [] and @board.first_page? and @board.filter.type}
            board={@board}
          />
          <Regent.Primitives.empty_state
            :if={@board.cards == [] and not @board.first_page?}
            class="kf-empty"
            title="There is nothing more here."
          >
            <:action>
              <.link
                id="workspace-first-page"
                class="rg-button rg-button--secondary"
                patch={@board.first_page}
              >
                <span class="rg-button__label">Back to the first page</span>
              </.link>
            </:action>
          </Regent.Primitives.empty_state>

          <.goal_rows
            :if={@board.cards != [] and @board.filter.type == "goal"}
            id="workspace-cards"
            rows={@board.cards}
            fleet_id={@board.fleet_id}
          />
          <ol
            :if={@board.cards != [] and @board.filter.type != "goal"}
            id="workspace-cards"
            class="workspace-cards"
            phx-hook="MotionCascade"
            data-variant={RegentsWeb.Motion.standard("grid")}
          >
            <.card :for={card <- @board.cards} card={card} fleet_id={@board.fleet_id} />
          </ol>

          <nav
            :if={@board.pages.previous || @board.pages.next}
            class="workspace-pages"
            aria-label="More items"
          >
            <.link :if={@board.pages.previous} id="workspace-previous" patch={@board.pages.previous}>
              Previous
            </.link>
            <.link :if={@board.pages.next} id="workspace-next" patch={@board.pages.next}>
              Next
            </.link>
          </nav>
        </section>
      </div>
      <div class="workspace-side">
        <section
          id="workspace-project-info"
          class="rg-panel workspace-info"
          aria-labelledby="workspace-project-info-title"
        >
          <div class="rg-panel__body">
            <h3 id="workspace-project-info-title">
              Workflow
              <Regent.Primitives.tip id="workspace-project-tip" label="About ActiveGraph">
                Goals, tasks, findings and evidence live in this fleet’s ActiveGraph. Agents write them; every change shows in the workstream.
              </Regent.Primitives.tip>
            </h3>
            <ul class="workspace-info-rules">
              <li>Any Key joins a task and works on it.</li>
              <li>Only its creator changes what it asks for, or archives it.</li>
              <li>A Key that worked on a task never reviews it.</li>
              <li>Any Key forks its own copy, linked back to the task.</li>
            </ul>
            <.agent_guide />
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :board, :map, required: true

  # The items and the links between them as a tree on an endless canvas,
  # each coloured by where it stands and arranged as the address says, above
  # the same items as a list, each with its links in words. Pressing an
  # item's title in either opens its page (`RegentsWeb.Keyfleet.WorkspaceGraph`).
  defp graph_view(assigns) do
    assigns =
      assign(assigns,
        graph: assigns.board.graph,
        filter: assigns.board.filter,
        goal: Enum.find(assigns.board.graph.rows, &(&1.id == assigns.board.filter.goal)),
        step: step(assigns.board.goals, assigns.board.filter.goal),
        tasks: Enum.filter(assigns.board.graph.nodes, &(&1.type == "task")),
        filtered?:
          assigns.board.filter.type != nil or assigns.board.filter.owner != nil or
            assigns.board.filter.goal != nil or assigns.board.filter.archived?
      )

    ~H"""
    <section
      id="workspace-graph"
      class="workspace-panel workspace-graph"
      aria-labelledby="workspace-graph-title"
    >
      <header class="workspace-graph-head">
        <h2 id="workspace-graph-title">Graph</h2>
        <p id="workspace-graph-count" class="workspace-detail">
          <span>{count(length(@graph.nodes), "item", "items")}</span>
          <span>{count(length(@graph.edges), "link", "links")}</span>
          <span :if={@graph.more_nodes?}>The {length(@graph.nodes)} most recently changed</span>
          <span :if={@graph.more_edges?}>The first {length(@graph.edges)} links</span>
        </p>
      </header>

      <div class="workspace-graph-filters">
        <nav class="workspace-filters" aria-label="Kinds of item">
          <.link
            :for={{type, label} <- [{nil, "Everything"} | kinds()]}
            patch={WorkspacePage.board_path(@board.fleet_id, %{@filter | type: type})}
            aria-current={if @filter.type == type, do: "page"}
            data-type-filter={type || "all"}
          >
            {label}
          </.link>
        </nav>
        <nav id="workspace-graph-owners" class="workspace-filters" aria-label="Owners">
          <.link
            :for={{owner, label} <- owners(@graph.owners, @filter.owner, @board.you)}
            patch={WorkspacePage.board_path(@board.fleet_id, %{@filter | owner: owner})}
            aria-current={if @filter.owner == owner, do: "page"}
            data-owner-filter={owner || "all"}
          >
            {label}
          </.link>
        </nav>
        <.link
          id="workspace-graph-archived"
          class="workspace-toggle"
          patch={
            WorkspacePage.board_path(@board.fleet_id, %{@filter | archived?: not @filter.archived?})
          }
        >
          {if @filter.archived?, do: "Hide archived items", else: "Show archived items"}
        </.link>
      </div>

      <div id="workspace-stage" class="workspace-stage">
        <header class="workspace-stage-head">
          <p class="workspace-stage-live">
            <span class="workspace-stage-dot" aria-hidden="true"></span>
            <span>Live</span>
            <span>{@board.fleet_name}</span>
            <span :if={@filter.project}>{title(@board.projects, @filter.project)}</span>
          </p>
          <RegentsWeb.Keyfleet.Time.local
            :if={@graph.newest}
            id="workspace-stage-newest"
            at={@graph.newest}
            as={:stamp}
          />
        </header>

        <nav
          :if={@board.goals != [] or @filter.goal}
          id="workspace-step"
          class="workspace-map-card workspace-step"
          data-tone={if @goal, do: @goal.tone, else: "plain"}
          aria-label="Goals"
        >
          <p class="workspace-kind">
            {cond do
              is_nil(@filter.goal) -> "Every goal"
              @step.at -> "Goal #{@step.at} of #{length(@board.goals)}"
              true -> "Goal"
            end}
          </p>
          <p :if={is_nil(@filter.goal)} class="workspace-step-title">
            {count(length(@board.goals), "goal", "goals")}
          </p>
          <p :if={@filter.goal} id="workspace-graph-goal" class="workspace-step-title">
            <.link :if={@goal} patch={@goal.path}>{@goal.title}</.link>
            <span :if={is_nil(@goal)}>{@filter.goal}</span>
          </p>
          <p :if={@filter.goal} class="workspace-detail">
            <span>{count(length(@tasks), "task", "tasks")}</span>
            <span>{Enum.count(@tasks, &(&1.tone == :waiting))} awaiting review</span>
          </p>
          <p class="workspace-step-moves">
            <.link
              :if={@step.back}
              id="workspace-step-back"
              class="workspace-step-move"
              patch={@step.back.path}
              title={@step.back.title}
              aria-label={"Goal before: #{@step.back.title}"}
            >
              <Regent.Icons.icon name="chevron-left" />
            </.link>
            <.link
              :if={@step.on}
              id="workspace-step-on"
              class="workspace-step-move"
              patch={@step.on.path}
              title={@step.on.title}
              aria-label={"Next goal: #{@step.on.title}"}
            >
              <Regent.Icons.icon name="chevron-right" />
            </.link>
            <.link
              :if={@filter.goal}
              id="workspace-graph-every-goal"
              class="workspace-toggle"
              patch={WorkspacePage.board_path(@board.fleet_id, %{@filter | goal: nil})}
            >
              Every goal
            </.link>
          </p>
        </nav>

        <Regent.Primitives.empty_state
          :if={@graph.nodes == []}
          id="workspace-graph-empty"
          class="kf-empty"
          title={if @filtered?, do: "No items match these filters.", else: "Nothing here yet."}
        >
          <:action :if={@filtered?}>
            <.link
              class="rg-button rg-button--secondary"
              patch={WorkspacePage.board_path(@board.fleet_id, graph_filter(@filter))}
            >
              <span class="rg-button__label">Show everything</span>
            </.link>
          </:action>
        </Regent.Primitives.empty_state>

        <.arrange
          :if={@graph.nodes != []}
          id="workspace-graph-arrange"
          at={@filter}
          to={&WorkspacePage.board_path(@board.fleet_id, &1)}
        />
        <.tree_canvas
          :if={@graph.nodes != []}
          id="workspace-graph-tree"
          tree={@board.canvas}
          at={@filter}
          label="Graph"
        />

        <ol
          id="workspace-ticker"
          class="workspace-ticker"
          aria-label="Newest change"
          phx-hook="MotionList"
          data-variant={RegentsWeb.Motion.standard("list")}
          data-layout-id="workspace-ticker"
          data-children="[data-tick]"
        >
          <li
            :for={line <- Enum.take(@board.instruments.workstream, 1)}
            id={"workspace-ticker-#{line.seq}"}
            data-tick
            data-layout-id={"workspace-ticker-#{line.seq}"}
          >
            <span><.line parts={line.parts} fleet_id={@board.fleet_id} /></span>
            <RegentsWeb.Keyfleet.Time.local
              id={"workspace-ticker-#{line.seq}-at"}
              class="workspace-detail"
              at={line.at}
              as={:clock}
              title_as={:moment}
            />
          </li>
        </ol>
      </div>

      <ul
        :if={@graph.tones != []}
        id="workspace-graph-key"
        class="workspace-graph-key"
        aria-label="Status"
      >
        <li :for={tone <- @graph.tones} data-tone={tone.tone}>
          <span class="workspace-graph-mark" aria-hidden="true"></span>
          {tone.name} <span class="workspace-detail">{tone.count}</span>
        </li>
      </ul>

      <.instruments board={@board} at_work={at_work(@graph.nodes)} />

      <ol :if={@graph.nodes != []} id="workspace-graph-list" class="workspace-graph-list">
        <li :for={row <- @graph.rows} data-row={row.id} data-tone={row.tone}>
          <p class="workspace-kind">
            <span class="workspace-graph-mark" aria-hidden="true"></span>
            <span>{row.kind}</span>
            <span :if={row.standing}>{row.standing}</span>
            <span :if={row.archived?} class="workspace-badge">Archived</span>
          </p>
          <h3><.link patch={row.path}>{row.title}</.link></h3>
          <p :if={row.owner || row.project} class="workspace-detail">
            <span :if={row.owner}>{row.owner}</span>
            <span :if={row.project} data-project-label>{row.project}</span>
          </p>
          <ul :if={row.links != []} class="workspace-graph-links">
            <li :for={{direction, words, other} <- row.links}>
              <span :if={direction == :to}>
                {String.capitalize(words)} <.link patch={other.path}>{other.title}</.link>
              </span>
              <span :if={direction == :from}>
                <.link patch={other.path}>{other.title}</.link> {words} this
              </span>
            </li>
          </ul>
        </li>
      </ol>
    </section>
    """
  end

  attr :board, :map, required: true
  attr :at_work, :list, required: true

  # Four small panels under the stage, each a short list: the newest of the
  # workstream, each Key's tasks in the picture by where they stand, and
  # what members pinned in the Docs and the Code. Each opens the whole of it.
  defp instruments(assigns) do
    assigns = assign(assigns, project: assigns.board.filter.project)

    ~H"""
    <div id="workspace-instruments" class="workspace-instruments">
      <section class="workspace-instrument" aria-labelledby="workspace-instrument-work-title">
        <h3 id="workspace-instrument-work-title">Workstream</h3>
        <p :if={@board.instruments.workstream == []} class="workspace-detail">
          Nothing has happened yet.
        </p>
        <ol :if={@board.instruments.workstream != []} id="workspace-instrument-work">
          <li :for={line <- @board.instruments.workstream} data-seq={line.seq}>
            <.line parts={line.parts} fleet_id={@board.fleet_id} />
          </li>
        </ol>
        <.link class="workspace-toggle" patch={view_path(@board, :board)}>More</.link>
      </section>

      <section class="workspace-instrument" aria-labelledby="workspace-instrument-keys-title">
        <h3 id="workspace-instrument-keys-title">Active Keys</h3>
        <p :if={@at_work == []} class="workspace-detail">No Key has joined a task here yet.</p>
        <ol :if={@at_work != []} id="workspace-instrument-keys">
          <li :for={key <- @at_work} data-key={key.key}>
            <span>{key.name}</span>
            <span
              class="workspace-instrument-bar"
              role="img"
              aria-label={"#{key.doing} in progress, #{key.waiting} awaiting review, #{key.done} done"}
              title={"#{key.doing} in progress, #{key.waiting} awaiting review, #{key.done} done"}
              style={"width: #{key.share}%"}
            >
              <span
                :for={{tone, count} <- [doing: key.doing, waiting: key.waiting, done: key.done]}
                :if={count > 0}
                data-tone={tone}
                style={"flex-grow: #{count}"}
              ></span>
            </span>
          </li>
        </ol>
      </section>

      <section
        :for={{place, title} <- [docs: "Docs", code: "Code"]}
        class="workspace-instrument"
        aria-labelledby={"workspace-instrument-#{place}-title"}
      >
        <h3 id={"workspace-instrument-#{place}-title"}>{title}</h3>
        <p :if={@board.instruments[place] == []} class="workspace-detail">Nothing pinned yet.</p>
        <ol :if={@board.instruments[place] != []} id={"workspace-instrument-#{place}"}>
          <li :for={pin <- @board.instruments[place]} data-pin={pin.target}>
            <a :if={place == :docs and pin.link} href={pin.link}>{pin.title}</a>
            <span :if={place == :docs and is_nil(pin.link)}>{pin.title}</span>
            <.link :if={place == :code} patch={pin.link}>{pin.title}</.link>
            <span :if={pin.label} class="workspace-project-tag" data-project-label>{pin.label}</span>
          </li>
        </ol>
        <.link
          class="workspace-toggle"
          patch={WorkspacePage.place_path(@board.fleet_id, place, @project)}
        >
          More
        </.link>
      </section>
    </div>
    """
  end

  # Each Key that joined tasks in the picture, lowest first, with how many
  # of them are in progress, awaiting review and done, and its share of the
  # bar, against the Key that joined the most.
  defp at_work(nodes) do
    joined =
      for %{type: "task", tone: tone} = node <- nodes,
          tone in [:doing, :waiting, :done],
          key <- node.joined_keys do
        {key, node}
      end
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort()

    most = joined |> Enum.map(fn {_key, tasks} -> length(tasks) end) |> Enum.max(fn -> 1 end)

    for {key, tasks} <- joined do
      tones = Enum.frequencies_by(tasks, & &1.tone)

      %{
        key: key,
        name: ActivityLines.key_name(key, nil),
        doing: Map.get(tones, :doing, 0),
        waiting: Map.get(tones, :waiting, 0),
        done: Map.get(tones, :done, 0),
        share: div(length(tasks) * 100, most)
      }
    end
  end

  # Where the Graph view stands among the goals it steps through: the goal
  # shown, counted from 1, and the goals before and after it. With no goal
  # shown, the step on is to the first.
  defp step(goals, nil), do: %{at: nil, back: nil, on: List.first(goals)}

  defp step(goals, goal) do
    case Enum.find_index(goals, &(&1.id == goal)) do
      nil ->
        %{at: nil, back: nil, on: nil}

      index ->
        %{
          at: index + 1,
          back: index > 0 && Enum.at(goals, index - 1),
          on: Enum.at(goals, index + 1)
        }
    end
  end

  defp count(1, one, _many), do: "1 #{one}"
  defp count(number, _one, many), do: "#{number} #{many}"

  # Everyone, the member's own Key, then each Key that owns any of the items
  # drawn, with how many; the Key chosen stays offered while it owns none.
  defp owners(owners, chosen, you) do
    yours = you && you.key
    mine = if yours, do: [{yours, "Your Key"}], else: []

    others =
      for %{key: key, items: items} <- owners,
          key != yours,
          do: {key, "#{key_label(key)} · #{items}"}

    kept =
      if chosen && chosen != yours && chosen not in Enum.map(owners, & &1.key),
        do: [{chosen, key_label(chosen)}],
        else: []

    [{nil, "Everyone"}] ++ mine ++ others ++ kept
  end

  defp key_label(key), do: ActivityLines.key_name(key, nil)

  attr :board, :map, required: true
  attr :notice, :string, default: nil

  # One project's newest notebooks, grouped by folder, or each project's few
  # newest in turn, beside what the fleet's members pinned and how to open
  # them.
  defp docs(assigns) do
    ~H"""
    <div class="workspace-grid">
      <div class="workspace-main">
        <section
          id="workspace-notebooks"
          class="workspace-panel"
          aria-labelledby="workspace-notebooks-title"
        >
          <h2 id="workspace-notebooks-title">Notebooks</h2>
          <Regent.Primitives.empty_state
            :if={not @board.hub?}
            id="workspace-notebooks-none"
            class="kf-empty"
            title="Notebooks aren’t connected for this fleet yet."
          />
          <nav
            :if={@board.hub?}
            id="workspace-docs-views"
            class="workspace-views"
            aria-label="Notebook views"
          >
            <.link
              :for={{view, label} <- [canvas: "Canvas", list: "List"]}
              id={"workspace-docs-view-#{view}"}
              class="rg-panel"
              patch={
                WorkspacePage.docs_path(@board.fleet_id, @board.project, %{@board.docs | view: view})
              }
              aria-current={if @board.docs.view == view, do: "page"}
            >
              {label}
            </.link>
          </nav>
          <.notebook_canvas :if={@board.canvas} board={@board} />
          <.notebook_rows
            :if={@board.hub? and @board.project != nil and @board.docs.view == :list}
            notebooks={@board.notebooks}
            pins={@board.pins}
            project={@board.project}
            active?={@board.active?}
          />
          <section
            :for={
              section <- if(@board.hub? and @board.docs.view == :list, do: @board.sections, else: [])
            }
            id={"workspace-docs-#{section.project}"}
            class="workspace-folder"
            data-project={section.project}
          >
            <h3>
              <.link patch={section.link}>{section.title}</.link>
            </h3>
            <p :if={section.notebooks == :unreadable} class="workspace-detail">
              These notebooks can’t be read right now.
            </p>
            <p :if={section.notebooks == []} class="workspace-detail">No notebooks yet.</p>
            <ol :if={listed(section.notebooks) != []} class="workspace-rows">
              <li
                :for={notebook <- listed(section.notebooks)}
                class="workspace-row"
                data-notebook={notebook.id}
              >
                <a class="workspace-row-title" href={notebook.open}>{notebook.title}</a>
                <span class="workspace-row-meta">
                  <.changed_mark :if={notebook.changed_since_run?} />
                  <span :if={notebook.folder}>{notebook.folder}</span>
                  <RegentsWeb.Keyfleet.Time.local
                    id={"workspace-docs-#{section.project}-#{notebook.id}-added"}
                    at={notebook.added}
                    as={:date}
                  />
                </span>
              </li>
            </ol>
          </section>
        </section>
      </div>
      <div class="workspace-side">
        <.pins
          :if={@board.hub? or @board.pins != []}
          id="workspace-docs-pins"
          place={:docs}
          pins={@board.pins}
          empty="Pin a notebook to keep it here."
        />
        <section
          :if={@board.hub?}
          id="workspace-docs-info"
          class="rg-panel workspace-info"
          aria-labelledby="workspace-docs-info-title"
        >
          <div class="rg-panel__body">
            <h3 id="workspace-docs-info-title">
              Editing
              <Regent.Primitives.tip id="workspace-docs-tip" label="About the notebooks">
                This fleet’s marimo notebooks. Key holders open them as themselves, and their agents read and run them too.
              </Regent.Primitives.tip>
            </h3>
            <Regent.Primitives.button
              id="open-notebooks"
              phx-click="open_notebooks"
            >
              Open notebooks
            </Regent.Primitives.button>
            <p :if={@notice} id="notebooks-notice" class="workspace-notebooks-notice">{@notice}</p>
          </div>
        </section>
        <section
          :if={@board.project && @board.active? && @board.copies != []}
          id="workspace-copies"
          class="rg-panel workspace-info"
          aria-labelledby="workspace-copies-title"
        >
          <div class="rg-panel__body">
            <h3 id="workspace-copies-title">
              Daily copies
              <Regent.Primitives.tip id="workspace-copies-tip" label="About daily copies">
                Each notebook that changed is copied once a day and kept for 90 days. Bringing one back makes a new notebook, yours.
              </Regent.Primitives.tip>
            </h3>
            <form
              :for={notebook <- @board.copies}
              id={"workspace-copies-#{notebook.notebook_id}"}
              class="workspace-copy-form"
              phx-submit="notebook_restore"
            >
              <input type="hidden" name="project" value={@board.project} />
              <label>
                <span>{notebook.title}</span>
                <select name="copy">
                  <option :for={copy <- notebook.copies} value={copy.id}>
                    {Calendar.strftime(copy.changed_at, "%-d %b %Y")}
                  </option>
                </select>
              </label>
              <Regent.Primitives.button type="submit" variant="secondary">
                Bring back
              </Regent.Primitives.button>
            </form>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :board, :map, required: true

  # The notebooks shown, one project's or each project's newest, as a tree
  # canvas with the tasks that name them, and which projects' notebooks
  # can't be read now.
  defp notebook_canvas(assigns) do
    assigns =
      assign(assigns,
        unread: for(%{notebooks: :unreadable, title: title} <- assigns.board.sections, do: title),
        drawn?: assigns.board.canvas.cards != []
      )

    ~H"""
    <p :if={@board.notebooks == :unreadable} id="workspace-notebooks-unreadable">
      The notebooks can’t be read right now. Try again in a minute.
    </p>
    <p :if={@unread != []} id="workspace-docs-unreadable" class="workspace-detail">
      Not read right now: {Enum.join(@unread, ", ")}
    </p>
    <Regent.Primitives.empty_state
      :if={not @drawn? and @unread == [] and @board.notebooks != :unreadable}
      id="workspace-notebooks-empty"
      class="kf-empty"
      title="No notebooks yet."
    >
      Open the notebooks to start the first one.
    </Regent.Primitives.empty_state>
    <.arrange
      :if={@drawn?}
      id="workspace-docs-arrange"
      at={@board.docs}
      to={&WorkspacePage.docs_path(@board.fleet_id, @board.project, &1)}
    />
    <.tree_canvas
      :if={@drawn?}
      id="workspace-docs-tree"
      tree={@board.canvas}
      at={@board.docs}
      label="Notebooks"
    />
    """
  end

  attr :id, :string, required: true
  attr :at, :map, required: true, doc: "the arrangement shown, its `arrange` and `every`"
  attr :to, :any, required: true, doc: "the path showing the arrangement it is given"

  # How a tree canvas is arranged: by when each card was made, in slices of
  # an hour or a day, by the Key that made it, or by how recently it
  # changed. Each choice opens its own address.
  defp arrange(assigns) do
    ~H"""
    <div id={@id} class="tree-canvas-arrange">
      <div class="tree-canvas-segments" role="group" aria-labelledby={"#{@id}-label"}>
        <span id={"#{@id}-label"} class="tree-canvas-arrange-label">Arrange</span>
        <button
          :for={{arrange, label} <- [time: "Time", author: "Author", activity: "Activity"]}
          id={"#{@id}-#{arrange}"}
          type="button"
          phx-click={JS.patch(@to.(%{@at | arrange: arrange}))}
          aria-pressed={to_string(@at.arrange == arrange)}
        >
          {label}
        </button>
      </div>
      <div
        :if={@at.arrange == :time}
        class="tree-canvas-segments"
        role="group"
        aria-label="Slices"
      >
        <button
          :for={{every, label} <- [hour: "Hourly", day: "Daily"]}
          id={"#{@id}-#{every}"}
          type="button"
          phx-click={JS.patch(@to.(%{@at | every: every}))}
          aria-pressed={to_string(@at.every == every)}
        >
          {label}
        </button>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :tree, :map, required: true, doc: "the cards and links, as the canvas reads them"
  attr :at, :map, required: true, doc: "the arrangement shown, its `arrange` and `every`"
  attr :label, :string, required: true

  # An endless surface of cards and the links between them, drawn in the
  # browser (the `TreeCanvas` hook) from `tree`; the page changes only what
  # it draws and how it is arranged. Its corner zooms and fits it.
  defp tree_canvas(assigns) do
    ~H"""
    <div
      id={@id}
      class="tree-canvas"
      phx-hook="TreeCanvas"
      data-tree={Jason.encode!(@tree)}
      data-arrange={@at.arrange}
      data-every={@at.every}
    >
      <div id={"#{@id}-stage"} class="tree-canvas-stage" phx-update="ignore">
        <div class="tree-canvas-surface" role="group" aria-label={@label} data-tree-surface>
          <div class="tree-canvas-grid" aria-hidden="true" data-tree-grid></div>
          <div class="tree-canvas-world" aria-hidden="true" data-tree-back></div>
          <canvas class="tree-canvas-glow" aria-hidden="true" data-tree-canvas></canvas>
          <div class="tree-canvas-world" data-tree-front>
            <svg class="tree-canvas-links" aria-hidden="true" data-tree-links></svg>
            <div data-tree-cards></div>
          </div>
          <div class="tree-canvas-headings" aria-hidden="true" data-tree-headings></div>
        </div>
        <div class="tree-canvas-zoom" role="group" aria-label="Zoom">
          <button type="button" aria-label="Zoom out" data-tree-zoom="out">−</button>
          <output aria-label="Zoom" data-tree-zoom-level>100%</output>
          <button type="button" aria-label="Zoom in" data-tree-zoom="in">+</button>
          <button type="button" data-tree-zoom="fit">Fit</button>
        </div>
      </div>
    </div>
    """
  end

  attr :notebooks, :any, required: true, doc: "the notebooks as read, or `:unreadable`"
  attr :pins, :list, required: true
  attr :project, :string, required: true
  attr :active?, :boolean, required: true

  # One project's notebooks, those in no folder first, then each folder
  # under its name.
  defp notebook_rows(assigns) do
    ~H"""
    <p :if={@notebooks == :unreadable} id="workspace-notebooks-unreadable">
      The notebooks can’t be read right now. Try again in a minute.
    </p>
    <Regent.Primitives.empty_state
      :if={@notebooks == []}
      id="workspace-notebooks-empty"
      class="kf-empty"
      title="No notebooks yet."
    >
      Open the notebooks to start the first one.
    </Regent.Primitives.empty_state>
    <div :if={listed(@notebooks) != []} id="workspace-notebook-rows" class="workspace-folders">
      <section
        :for={{folder, notebooks} <- by_folder(listed(@notebooks))}
        class="workspace-folder"
        data-folder={folder}
      >
        <h3 :if={folder}>{folder}</h3>
        <ol class="workspace-rows">
          <li
            :for={notebook <- notebooks}
            class="workspace-row workspace-row--pinnable"
            data-notebook={notebook.id}
          >
            <a class="workspace-row-title" href={notebook.open}>{notebook.title}</a>
            <span class="workspace-row-meta">
              <.changed_mark :if={notebook.changed_since_run?} />
              <span id={"workspace-notebook-#{notebook.id}-lock"}>
                {if notebook.locked, do: "Locked", else: "Anyone edits"}
              </span>
              <RegentsWeb.Keyfleet.Time.local
                id={"workspace-notebook-#{notebook.id}-added"}
                at={notebook.added}
                as={:date}
              />
              <button
                :if={notebook.creator? and @active?}
                id={"workspace-notebook-#{notebook.id}-switch"}
                type="button"
                class="workspace-row-switch"
                phx-click="notebook_lock"
                phx-value-project={@project}
                phx-value-notebook={notebook.id}
                phx-value-locked={to_string(not notebook.locked)}
              >
                {if notebook.locked, do: "Unlock", else: "Lock"}
              </button>
            </span>
            <p :if={notebook.description != ""} class="workspace-row-text">
              {notebook.description}
            </p>
            <.pin_toggle
              id={"workspace-notebook-#{notebook.id}-pin"}
              place={:docs}
              project={@project}
              active?={@active?}
              target={notebook.id}
              name={notebook.title}
              whose={whose(@pins, notebook.id)}
            />
          </li>
        </ol>
      </section>
    </div>
    """
  end

  # A notebook changed since its newest kept run page, whose page may no
  # longer show what its code does: one word, read out in full.
  defp changed_mark(assigns) do
    ~H"""
    <Regent.Primitives.status data-changed-since-run>
      Changed<span class="visually-hidden"> since its last run</span>
    </Regent.Primitives.status>
    """
  end

  attr :board, :map, required: true
  attr :password, :map, default: nil, doc: "the git password just made, and until when"
  attr :notice, :string, default: nil

  # One project's code: its top folder and the changes sent lately, beside
  # what the members pinned, where git copies it from, and a password for a
  # holder of one of the fleet's Keys. Across all projects, each project's
  # repository in turn, and every pin.
  defp code(assigns) do
    ~H"""
    <div class="workspace-grid">
      <div class="workspace-main">
        <section
          :if={is_nil(@board.project)}
          id="workspace-code"
          class="workspace-panel"
          aria-labelledby="workspace-code-title"
        >
          <h2 id="workspace-code-title">Repositories</h2>
          <ol id="workspace-repositories" class="workspace-rows">
            <li
              :for={repository <- @board.repositories}
              class="workspace-row"
              data-project={repository.project}
            >
              <.link class="workspace-row-title" patch={repository.link}>{repository.title}</.link>
              <span class="workspace-row-meta">
                {holder(repository.key)}
                <span :if={repository.state == :archived} class="workspace-badge">Archived</span>
              </span>
              <div class="workspace-copy-box">
                <code id={"workspace-code-address-#{repository.project}"}>
                  {repository.clone_url}
                </code>
                <Regent.Primitives.copy_icon
                  id={"workspace-code-address-#{repository.project}-copy"}
                  target={"workspace-code-address-#{repository.project}"}
                  label={"Copy the address of #{repository.title}’s code"}
                />
              </div>
            </li>
          </ol>
        </section>

        <section
          :if={@board.project}
          id="workspace-code"
          class="workspace-panel"
          aria-labelledby="workspace-code-title"
        >
          <h2 id="workspace-code-title">Files</h2>
          <p :if={@board.files == :unreadable} id="workspace-code-unreadable">
            The code can’t be read right now. Try again in a minute.
          </p>
          <Regent.Primitives.empty_state
            :if={@board.files == [] and @board.pushes == []}
            id="workspace-code-empty"
            class="kf-empty"
            title="No code has been sent yet."
          />
          <Regent.Primitives.empty_state
            :if={@board.files == [] and @board.pushes != []}
            id="workspace-code-main-empty"
            class="kf-empty"
            title="No files on main yet."
          />
          <ol :if={entries(@board.files) != []} id="workspace-code-rows" class="workspace-rows">
            <li
              :for={entry <- entries(@board.files)}
              class="workspace-row workspace-row--pinnable"
              data-file={entry.path}
            >
              <span class="workspace-kind">{if entry.folder?, do: "Folder", else: "File"}</span>
              <.link class="workspace-row-title" patch={entry.link}>{entry.name}</.link>
              <span :if={entry.size} class="workspace-row-meta">{size(entry.size)}</span>
              <.pin_toggle
                id={"workspace-code-#{entry_id(entry.path)}-pin"}
                place={:code}
                project={@board.project}
                active?={@board.active?}
                target={entry.path}
                name={entry.path}
                whose={whose(@board.pins, entry.path)}
              />
            </li>
          </ol>
          <p :if={entries(@board.files) != []} class="code-actions">
            <.link
              id="workspace-code-files"
              patch={Regents.Keyfleet.Code.files_path(@board.fleet_id, @board.repository, "")}
            >
              Browse the code
            </.link>
            <.link id="workspace-code-history" patch={@board.history_link}>History</.link>
          </p>
        </section>

        <section
          :if={@board.project}
          class="workspace-panel"
          aria-labelledby="workspace-code-pushes-title"
        >
          <h2 id="workspace-code-pushes-title">Pushes</h2>
          <Regent.Primitives.empty_state
            :if={@board.pushes == []}
            id="code-pushes-empty"
            class="kf-empty"
            title="No changes have been sent yet."
          />
          <.feed :let={push} :if={@board.pushes != []} id="code-pushes" rows={@board.pushes} key={:id}>
            <p>
              <.key fleet_id={@board.fleet_id} token_id={push.token_id} agent={push.agent} />
              sent {push.what}, ending at <.value value={push.commit} fleet_id={@board.fleet_id} />
            </p>
          </.feed>
        </section>
      </div>
      <div class="workspace-side">
        <.pins
          id="workspace-code-pins"
          place={:code}
          pins={@board.pins}
          empty="Pin a file or folder to keep it here."
        />
        <section
          id="workspace-code-info"
          class="rg-panel workspace-info"
          aria-labelledby="workspace-code-info-title"
        >
          <div class="rg-panel__body">
            <h3 id="workspace-code-info-title">
              Clone
              <Regent.Primitives.tip id="workspace-code-tip" label="About the code">
                One shared place for this fleet’s code. Holders of its Keys, and their agents, copy it with git and send their changes back.
              </Regent.Primitives.tip>
            </h3>
            <div :if={@board.project} class="workspace-copy-box">
              <code id="workspace-code-address">{@board.clone_url}</code>
              <Regent.Primitives.copy_icon
                id="workspace-code-address-copy"
                target="workspace-code-address"
                label="Copy the code’s address"
              />
            </div>
            <Regent.Primitives.button id="get-code-password" phx-click="get_code_password">
              Get a git password
            </Regent.Primitives.button>
            <div :if={@password} id="code-password" class="workspace-code-password">
              <p>
                Good until
                <RegentsWeb.Keyfleet.Time.local
                  id="code-password-until"
                  at={@password.until}
                  as={:stamp}
                />.
                <Regent.Primitives.tip id="code-password-tip" label="About the git password">
                  Paste it when git asks for a password. It stops working sooner if you sign out or no longer hold a Key.
                </Regent.Primitives.tip>
              </p>
              <div class="workspace-copy-box">
                <code id="code-password-text">{@password.password}</code>
                <Regent.Primitives.copy_icon
                  id="code-password-copy"
                  target="code-password-text"
                  label="Copy the git password"
                />
              </div>
            </div>
            <p :if={@notice} id="code-notice" class="workspace-notebooks-notice">{@notice}</p>
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :place, :atom, required: true
  attr :pins, :list, required: true
  attr :empty, :string, required: true

  # What the fleet's members pinned in one place, newest first, each opening
  # what it names and unpinned from here.
  defp pins(assigns) do
    ~H"""
    <section
      id={@id}
      class="rg-panel workspace-info"
      aria-labelledby={@id <> "-title"}
    >
      <div class="rg-panel__body">
        <h3 id={@id <> "-title"}>Pinned</h3>
        <p :if={@pins == []} id={@id <> "-empty"} class="workspace-detail">{@empty}</p>
        <ol :if={@pins != []} id={@id <> "-rows"} class="workspace-pins">
          <li :for={pin <- @pins} data-pin={pin.target} data-project={pin.project}>
            <a :if={@place == :docs and pin.link} href={pin.link}>{pin.title}</a>
            <span :if={@place == :docs and is_nil(pin.link)}>{pin.title}</span>
            <.link :if={@place == :code} patch={pin.link}>{pin.title}</.link>
            <span :if={pin.label} class="workspace-project-tag" data-project-label>{pin.label}</span>
            <.pin_toggle
              id={"#{@id}-#{pin.project}-#{entry_id(pin.target)}"}
              place={@place}
              project={pin.project}
              target={pin.target}
              name={pin.title}
              whose={pin.whose}
            />
          </li>
        </ol>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :place, :atom, required: true
  attr :project, :string, required: true
  attr :active?, :boolean, default: true, doc: "whether the project takes new pins"
  attr :target, :string, required: true
  attr :name, :string, required: true, doc: "what a press pins, read out and shown on hover"

  attr :whose, :atom,
    values: [nil, :mine, :theirs],
    doc: "whose pin is on it, if any: only its pinner lifts a pin"

  # A pin a press sets or lifts, for every member of the fleet to see. Another
  # member's pin shows pinned, but only they lift it. An archived project
  # takes no new pins.
  defp pin_toggle(assigns) do
    ~H"""
    <button
      :if={@active? or @whose != nil}
      id={@id}
      type="button"
      class="kf-pin"
      aria-pressed={to_string(@whose != nil)}
      aria-label={pin_label(@whose, @name)}
      title={pin_title(@whose)}
      disabled={@whose == :theirs}
      phx-click={if @whose == :mine, do: "unpin", else: "pin"}
      phx-value-place={@place}
      phx-value-project={@project}
      phx-value-target={@target}
    >
      <Regent.Icons.icon name="pin" />
    </button>
    """
  end

  defp whose(pins, target), do: Enum.find_value(pins, &(&1.target == target && &1.whose))

  defp pin_title(nil), do: "Pin"
  defp pin_title(:mine), do: "Unpin"
  defp pin_title(:theirs), do: "Pinned by another member"

  defp pin_label(:theirs, name), do: "#{name}, pinned by another member"
  defp pin_label(whose, name), do: "#{pin_title(whose)} #{name}"

  # An element id made from a path or a notebook's id, which may hold
  # characters an id can't.
  defp entry_id(target), do: Base.url_encode64(target, padding: false)

  defp agent_guide(assigns) do
    ~H"""
    <Regent.Primitives.disclosure id="workspace-agent-guide" summary="Agent guide">
      <p>
        Pair your agent with your account, then have it check access to this fleet.
      </p>
      <ol class="workspace-list">
        <li>Read the existing work. Choose a task and record the next step.</li>
        <li>Work in the repository or notebooks. Keep a commit or saved result as evidence.</li>
        <li>
          Add a note: what was tried, what happened, the evidence, and what comes next. Link it to the task.
        </li>
      </ol>
      <p><a href="/keyfleet/agents.md">Agent access</a> · <a href="/keyfleet/docs">Docs</a></p>
    </Regent.Primitives.disclosure>
    """
  end

  attr :item, :any, required: true, doc: "the item as read, or `:unreadable`"
  attr :publish_notice, :string, default: nil, doc: "why making the item public was refused"

  attr :signed_out?, :boolean,
    default: false,
    doc: "whether nobody is signed in, so the members-only page offers Sign in"

  def item(%{item: :unreadable} = assigns), do: ~H|<.unreadable id="workspace-item-page" />|

  def item(%{item: %{members_only?: true}} = assigns),
    do: ~H|<.members_only id="workspace-item-page" fleet={@item} signed_out?={@signed_out?} />|

  def item(assigns) do
    ~H"""
    <article id="workspace-item-page" class="workspace-page">
      <header class="workspace-heading">
        <p :if={@item.ready?} class="workspace-kicker">
          <.link patch={"#{Regents.Keyfleet.Fleets.path(@item.fleet_id)}/workspace"}>Workspace</.link>
        </p>
        <h2>{item_heading(@item)}</h2>
        <p :if={@item[:object]} class="workspace-lede">
          <span>{type_label(@item.object.type)}</span>
          <span :if={@item.object.starting?} class="workspace-badge">Starting idea</span>
          <span :if={@item.object.archived?} class="workspace-badge">Archived</span>
        </p>
      </header>

      <.public_notice />
      <.unavailable :if={not @item.ready?} />
      <.item_public :if={@item[:object]} public={@item.public} notice={@publish_notice} />

      <section :if={@item.ready? and is_nil(@item.object)} class="workspace-panel">
        <h2>This item isn’t in the workspace.</h2>
        <.link patch={"#{Regents.Keyfleet.Fleets.path(@item.fleet_id)}/workspace"}>See everything in the workspace</.link>
      </section>

      <div :if={@item[:object]} class="workspace-item-grid">
        <section class="workspace-panel" aria-labelledby="workspace-fields-title">
          <h2 id="workspace-fields-title">Details</h2>
          <dl id="workspace-fields" class="workspace-fields">
            <div :for={{label, value} <- @item.object.fields}>
              <dt>{label}</dt>
              <dd><.value value={value} fleet_id={@item.fleet_id} /></dd>
            </div>
          </dl>
          <p class="workspace-detail">
            <span>
              Added by <.part part={@item.object.by} fleet_id={@item.fleet_id} />
            </span>
            <span>
              Last changed
              <RegentsWeb.Keyfleet.Time.local
                id="workspace-item-changed-at"
                at={@item.object.changed_at}
                as={:stamp}
              />
            </span>
          </p>
        </section>

        <.goal_work :if={@item.goal} goal={@item.goal} fleet_id={@item.fleet_id} />

        <section :if={@item.links} class="workspace-panel" aria-labelledby="workspace-links-title">
          <h2 id="workspace-links-title">Linked items</h2>
          <Regent.Primitives.empty_state
            :if={@item.links.rows == [] and is_nil(@item.links.first)}
            class="kf-empty"
            title="Nothing is linked to this yet."
          />
          <Regent.Primitives.empty_state
            :if={@item.links.rows == [] and @item.links.first}
            class="kf-empty"
            title="There are no more links."
          />
          <ul :if={@item.links.rows != []} id="workspace-links" class="workspace-lines">
            <li
              :for={row <- @item.links.rows}
              data-relation={row.id}
              data-direction={if row.outgoing?, do: "from", else: "to"}
            >
              <span :if={row.outgoing?}>
                This {row.type_name} {row.relation}
                <.item_link
                  part={row.other}
                  fleet_id={@item.fleet_id}
                />
              </span>
              <span :if={not row.outgoing?}>
                <.item_link part={row.other} fleet_id={@item.fleet_id} /> {row.relation} this {row.type_name}
              </span>
            </li>
          </ul>
          <nav :if={@item.links.more || @item.links.first} class="workspace-pages">
            <.link :if={@item.links.first} id="workspace-first-links" patch={@item.links.first}>
              Back to the first links
            </.link>
            <.link :if={@item.links.more} id="workspace-more-links" patch={@item.links.more}>
              More links
            </.link>
          </nav>
        </section>

        <section class="workspace-panel" aria-labelledby="workspace-discussion-title">
          <h2 id="workspace-discussion-title">Discussion</h2>
          <Regent.Primitives.empty_state
            :if={@item.object.discussion == []}
            class="kf-empty"
            title="No one has mentioned this in the rooms yet."
          />
          <ul :if={@item.object.discussion != []} id="workspace-discussion" class="workspace-lines">
            <li :for={message <- @item.object.discussion}>
              <.link :if={message.path} patch={message.path}>
                Message {message.seq} in {message.room}
              </.link>
              <span :if={is_nil(message.path)}>Message {message.seq} in {message.room}</span>
            </li>
          </ul>
        </section>

        <section
          class="workspace-panel workspace-history"
          aria-labelledby="workspace-history-title"
        >
          <h2 id="workspace-history-title">History</h2>
          <Regent.Primitives.empty_state
            :if={@item.history.lines == []}
            class="kf-empty"
            title="There are no earlier changes."
          />
          <.feed
            :let={line}
            :if={@item.history.lines != []}
            id="workspace-history"
            rows={@item.history.lines}
            key={:seq}
          >
            <p><.line parts={line.parts} fleet_id={@item.fleet_id} /></p>
          </.feed>
          <nav :if={@item.history.more || @item.history.first} class="workspace-pages">
            <.link
              :if={@item.history.first}
              id="workspace-latest-history"
              patch={@item.history.first}
            >
              Back to the latest changes
            </.link>
            <.link :if={@item.history.more} id="workspace-more-history" patch={@item.history.more}>
              Earlier changes
            </.link>
          </nav>
        </section>
      </div>
    </article>
    """
  end

  attr :commit, :any, required: true, doc: "the commit as read, or `:unreadable`"
  attr :publish_notice, :string, default: nil, doc: "why making the code public was refused"

  attr :signed_out?, :boolean,
    default: false,
    doc: "whether nobody is signed in, so the members-only page offers Sign in"

  def commit(%{commit: :unreadable} = assigns), do: ~H|<.unreadable id="workspace-commit-page" />|

  def commit(%{commit: %{members_only?: true}} = assigns) do
    ~H"""
    <article id="workspace-commit-page" class="workspace-page">
      <header class="workspace-heading">
        <h2>Commit</h2>
        <p id="workspace-commit-members-only" class="workspace-lede">
          This commit is in {@commit.fleet_name}’s shared code. Its Key holders and their paired agents can read it.
        </p>
        <p class="workspace-detail"><code>{@commit.hash}</code></p>
        <.link patch={KeyLinks.members_path(@commit.fleet_id)}>See this fleet’s Keys</.link>
        <Regent.Primitives.button
          :if={@signed_out?}
          id="workspace-commit-sign-in"
          type="button"
          variant="secondary"
          data-account-target="sign-in"
        >
          Sign in
        </Regent.Primitives.button>
      </header>
    </article>
    """
  end

  def commit(assigns) do
    ~H"""
    <article id="workspace-commit-page" class="workspace-page code-commit">
      <header class="workspace-heading code-commit-heading">
        <p class="workspace-kicker">
          <.link patch={"#{Regents.Keyfleet.Fleets.path(@commit.fleet_id)}/workspace"}>Workspace</.link>
          <span aria-hidden="true">/</span>
          <.link id="workspace-commit-history" patch={@commit.history_link}>History</.link>
        </p>
        <h2 id="workspace-commit-subject">
          {if is_map(@commit.change),
            do: subject(@commit.change.subject),
            else: "Commit #{String.slice(@commit.hash, 0, 12)}"}
        </h2>
        <.byline
          id="workspace-commit-byline"
          fleet_id={@commit.fleet_id}
          sent={@commit.sent}
          author={is_map(@commit.change) && @commit.change.author}
          at={is_map(@commit.change) && @commit.change.at}
          hash={@commit.hash}
        />
      </header>

      <section
        :if={@commit.public.id || @commit.public.make? || @publish_notice}
        id="workspace-commit-public"
        class="workspace-panel workspace-item-public"
      >
        <p :if={@commit.public.id} class="workspace-detail">
          Everyone can read <.link patch={@commit.public.link}>the code at this commit</.link>, signed in or not.
        </p>
        <p :if={@commit.public.make?} class="workspace-detail">
          Show the code at this commit to everyone, read-only. Later changes stay with members.
        </p>
        <Regent.Primitives.button
          :if={@commit.public.make?}
          id="workspace-commit-publish"
          type="button"
          phx-click="publish_commit"
        >
          Make public
        </Regent.Primitives.button>
        <Regent.Primitives.button
          :if={@commit.public.take_back?}
          id="workspace-commit-withdraw"
          type="button"
          variant="secondary"
          phx-click="withdraw_publication"
          phx-value-id={@commit.public.id}
        >
          Take back
        </Regent.Primitives.button>
        <p
          :if={@publish_notice}
          id="workspace-commit-public-notice"
          class="workspace-notebooks-notice"
          role="status"
        >
          {@publish_notice}
        </p>
      </section>

      <div class="workspace-item-grid">
        <div class="workspace-wide code-commit-main">
          <section
            :if={is_map(@commit.change) and @commit.change.body}
            id="workspace-commit-message"
            class="workspace-panel"
            aria-label="Message"
          >
            <p class="code-message">{@commit.change.body}</p>
          </section>

          <section
            id="workspace-commit-changes"
            class="workspace-panel"
            aria-labelledby="workspace-commit-changes-title"
          >
            <h2 id="workspace-commit-changes-title">Changes</h2>
            <p :if={@commit.change == :unreadable} id="workspace-commit-unreadable">
              The code can’t be read right now. Try again in a minute.
            </p>
            <Regent.Primitives.empty_state
              :if={@commit.change == :not_found}
              id="workspace-commit-not-sent"
              class="kf-empty"
              title="This commit hasn’t been sent to the code yet."
            >
              Its changes show here once it arrives.
            </Regent.Primitives.empty_state>
            <.changes :if={is_map(@commit.change)} change={@commit.change} />
          </section>
        </div>

        <section class="workspace-panel" aria-labelledby="workspace-commit-title">
          <h2 id="workspace-commit-title">Details</h2>
          <dl class="workspace-fields">
            <div>
              <dt>Full commit</dt>
              <dd><code id="workspace-commit-hash">{@commit.hash}</code></dd>
            </div>
            <div :if={is_map(@commit.change) and @commit.change.parents != []}>
              <dt>{if length(@commit.change.parents) == 1, do: "Parent", else: "Parents"}</dt>
              <dd id="workspace-commit-parents">
                <p :for={parent <- @commit.change.parents}>
                  <.link patch={parent.link}><code>{String.slice(parent.hash, 0, 12)}</code></.link>
                </p>
              </dd>
            </div>
            <div>
              <dt>
                Citation link
                <Regent.Primitives.tip id="workspace-commit-link-tip" label="About">
                  Use this link as the source of evidence in the workspace. It always points at this exact change.
                </Regent.Primitives.tip>
              </dt>
              <dd class="workspace-code-line">
                <code id="workspace-commit-url">{@commit.url}</code>
                <Regent.Primitives.copy_button id="workspace-commit-url-copy" text={@commit.url}>
                  Copy
                </Regent.Primitives.copy_button>
              </dd>
            </div>
            <div>
              <dt>Fetch</dt>
              <dd id="workspace-commit-fetch">
                <p><code>git fetch {@commit.clone_url}</code></p>
                <p><code>git checkout {@commit.hash}</code></p>
              </dd>
            </div>
          </dl>
          <.link
            :if={is_map(@commit.change)}
            id="workspace-commit-files"
            class="code-action"
            patch={@commit.files_link}
          >
            Files
          </.link>
        </section>

        <section class="workspace-panel" aria-labelledby="workspace-commit-citing-title">
          <h2 id="workspace-commit-citing-title">Citation</h2>
          <Regent.Primitives.empty_state
            :if={@commit.citing == []}
            id="workspace-commit-no-citing"
            class="kf-empty"
            title="No task or evidence in the workspace cites this commit yet."
          />
          <ul :if={@commit.citing != []} id="workspace-commit-citing" class="workspace-lines">
            <li :for={work <- @commit.citing} data-item={work.id}>
              <p>
                <span class="workspace-kind">{type_label(work.type)}</span>
                <.link patch={WorkspacePage.item_path(@commit.fleet_id, work.id)}>
                  {work.title}
                </.link>
                <span :if={work.archived?} class="workspace-badge">Archived</span>
              </p>
              <p :if={work.excerpt} class="workspace-text">{work.excerpt}</p>
              <p :if={work.notebook} class="workspace-detail">
                Notebook <.value value={work.notebook} fleet_id={@commit.fleet_id} />
              </p>
              <p :if={work.result} class="workspace-detail">
                Result <.value value={work.result} fleet_id={@commit.fleet_id} />
              </p>
              <p :for={task <- work.tasks} class="workspace-detail">
                Produced by <.item_link part={task} fleet_id={@commit.fleet_id} />
              </p>
              <p class="workspace-detail">
                Added by <.part part={work.by} fleet_id={@commit.fleet_id} />
              </p>
            </li>
          </ul>
        </section>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :fleet_id, :string, required: true
  attr :sent, :map, default: nil, doc: "the Key and agent that sent the commit, and when"
  attr :author, :any, default: nil, doc: "the name the commit was written under"
  attr :at, :any, default: nil, doc: "when the commit was written"
  attr :hash, :string, required: true

  # Who sent a commit, by Key and agent as every byline on the site names
  # them, then the name it was written under and when, and its short hash.
  defp byline(assigns) do
    ~H"""
    <p id={@id} class="code-byline">
      <span :if={@sent} class="code-byline-sender">
        <.key fleet_id={@fleet_id} token_id={@sent.token_id} agent={@sent.agent} />
        <span class="workspace-detail">sent {@sent.what}</span>
      </span>
      <span :if={@author} class="workspace-detail">Written as {@author}</span>
      <RegentsWeb.Keyfleet.Time.local
        :if={@at}
        id={"#{@id}-at"}
        class="workspace-detail"
        at={@at}
        as={:stamp}
        title_as={:moment}
      />
      <span class="code-hash">
        <code id={"#{@id}-hash"}>{String.slice(@hash, 0, 12)}</code>
        <Regent.Primitives.copy_icon
          id={"#{@id}-hash-copy"}
          target={"#{@id}-full"}
          label="Copy the full commit"
        />
        <span id={"#{@id}-full"} class="visually-hidden">{@hash}</span>
      </span>
    </p>
    """
  end

  attr :change, :map, required: true

  # Each file a commit changed, with its lines: a short change opens with
  # its files open.
  defp changes(assigns) do
    ~H"""
    <p id="workspace-commit-summary" class="workspace-detail code-summary">
      {files_changed(length(@change.files))}
      <span class="code-added">+{Rules.grouped(@change.additions)}</span>
      <span class="code-removed">−{Rules.grouped(@change.deletions)}</span>
    </p>
    <div id="workspace-commit-file-list" class="code-files">
      <details
        :for={file <- @change.files}
        id={"workspace-commit-file-#{file.id}"}
        class="code-file"
        open={length(@change.files) <= 5}
      >
        <summary class="code-file-head">
          <Regent.Icons.icon name="chevron-right" class="code-file-mark" />
          <span class={"code-status code-status--#{file.status}"}>{change_label(file.status)}</span>
          <span class="code-file-path">
            <span :if={file.old_path} class="workspace-detail">{file.old_path} →</span>
            {file.path}
          </span>
          <span :if={not file.binary?} class="code-file-counts">
            <span class="code-added">+{Rules.grouped(file.additions)}</span>
            <span class="code-removed">−{Rules.grouped(file.deletions)}</span>
          </span>
        </summary>
        <p :if={file.binary?} class="workspace-detail code-file-note">
          This file isn’t text, so its lines aren’t shown.
        </p>
        <p :if={file.patch == "" and not file.binary?} class="workspace-detail code-file-note">
          Only the file’s mode or name changed.
        </p>
        <p :if={is_nil(file.patch) and not file.binary?} class="workspace-detail code-file-note">
          This change is too large to show here. Fetch the commit to read it.
        </p>
        <.diff :if={file.patch not in [nil, ""]} patch={file.patch} />
        <p :if={file.cut? and file.patch not in [nil, ""]} class="workspace-detail code-file-note">
          The rest of this file’s change is too large to show here.
        </p>
      </details>
    </div>
    <p :if={@change.files_cut?} id="workspace-commit-files-cut" class="workspace-detail">
      More files changed than show here. Fetch the commit to read them all.
    </p>
    """
  end

  attr :patch, :string, required: true

  # One file's changed lines, each numbered before and after.
  defp diff(assigns) do
    assigns = assign(assigns, :lines, RegentsWeb.Keyfleet.Diff.lines(assigns.patch))

    ~H"""
    <div class="code-diff-scroll">
      <table class="code-diff">
        <tbody>
          <tr :for={line <- @lines} class={"code-diff-row code-diff-row--#{line.kind}"}>
            <%= if line.kind == :hunk do %>
              <td class="code-diff-hunk" colspan="3">{line.text}</td>
            <% else %>
              <td class="code-diff-num">{line.old}</td>
              <td class="code-diff-num">{line.new}</td>
              <td class="code-diff-text" phx-no-format><span class="code-diff-sign" aria-hidden="true">{sign(line.kind)}</span>{line.text}</td>
            <% end %>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # A commit written with no message still needs words to open it by.
  defp subject(subject), do: if(String.trim(subject) == "", do: "No message", else: subject)

  defp files_changed(1), do: "1 file changed"
  defp files_changed(count), do: "#{count} files changed"

  defp change_label("added"), do: "Added"
  defp change_label("deleted"), do: "Deleted"
  defp change_label("renamed"), do: "Renamed"
  defp change_label("copied"), do: "Copied"
  defp change_label("type_changed"), do: "Type changed"
  defp change_label(_modified), do: "Changed"

  defp sign(:added), do: "+"
  defp sign(:removed), do: "−"
  defp sign(:same), do: " "

  attr :history, :any, required: true, doc: "the page of history as read, or `:unreadable`"

  attr :signed_out?, :boolean,
    default: false,
    doc: "whether nobody is signed in, so the members-only page offers Sign in"

  def history(%{history: :unreadable} = assigns),
    do: ~H|<.unreadable id="workspace-history-page" />|

  def history(%{history: %{members_only?: true}} = assigns) do
    ~H"""
    <article id="workspace-history-page" class="workspace-page">
      <header class="workspace-heading">
        <h2>History</h2>
        <p id="workspace-history-members-only" class="workspace-lede">
          This is {@history.fleet_name}’s shared code. Its Key holders and their paired agents can read it.
        </p>
        <.link patch={KeyLinks.members_path(@history.fleet_id)}>See this fleet’s Keys</.link>
        <Regent.Primitives.button
          :if={@signed_out?}
          id="workspace-history-sign-in"
          type="button"
          variant="secondary"
          data-account-target="sign-in"
        >
          Sign in
        </Regent.Primitives.button>
      </header>
    </article>
    """
  end

  def history(assigns) do
    ~H"""
    <article id="workspace-history-page" class="workspace-page">
      <header class="workspace-heading">
        <p class="workspace-kicker">
          <.link patch={"#{Regents.Keyfleet.Fleets.path(@history.fleet_id)}/workspace"}>Workspace</.link>
          <span aria-hidden="true">/</span>
          <.link id="workspace-history-files" patch={@history.files_link}>Code</.link>
        </p>
        <h2>History</h2>
      </header>

      <section
        id="workspace-history"
        class="workspace-panel code-history-panel"
        aria-label="History"
      >
        <p :if={@history.commits == :unreadable} id="workspace-history-unreadable">
          The code can’t be read right now. Try again in a minute.
        </p>
        <Regent.Primitives.empty_state
          :if={@history.commits == []}
          id="workspace-history-empty"
          class="kf-empty"
          title="No code has been sent yet."
        />
        <ol
          :if={is_list(@history.commits) and @history.commits != []}
          id="code-history"
          class="code-history"
          phx-hook="MotionList"
          data-variant={RegentsWeb.Motion.standard("list")}
          data-layout-id="code-history"
          data-children="[data-row]"
        >
          <li
            :for={commit <- @history.commits}
            id={"code-history-#{commit.hash}"}
            class="code-history-row"
            data-row
            data-layout-id={"code-history-#{commit.hash}"}
          >
            <div class="code-history-main">
              <.link class="code-history-subject" patch={commit.link}>{subject(commit.subject)}</.link>
              <p class="code-history-meta">
                <span :if={commit.sent}>
                  <.key
                    fleet_id={@history.fleet_id}
                    token_id={commit.sent.token_id}
                    agent={commit.sent.agent}
                  />
                </span>
                <span class="workspace-detail">Written as {commit.author}</span>
                <RegentsWeb.Keyfleet.Time.local
                  id={"code-history-#{commit.hash}-at"}
                  class="workspace-detail"
                  at={commit.at}
                  as={:stamp}
                  title_as={:moment}
                />
              </p>
              <p :if={commit.citing != []} class="code-history-cites">
                <.link
                  :for={work <- commit.citing}
                  class="code-chip"
                  patch={WorkspacePage.item_path(@history.fleet_id, work.id)}
                >
                  <span class="workspace-kind">{type_label(work.type)}</span>
                  {work.title || type_label(work.type)}
                </.link>
              </p>
            </div>
            <.link class="code-hash code-history-hash" patch={commit.link}>
              <code>{String.slice(commit.hash, 0, 7)}</code>
            </.link>
          </li>
        </ol>
        <nav
          :if={@history.newer || @history.older || @history.latest}
          class="workspace-pages"
          aria-label="Pages"
        >
          <.link :if={@history.latest} id="workspace-history-latest" patch={@history.latest}>
            Newest
          </.link>
          <.link :if={@history.newer} id="workspace-history-newer" patch={@history.newer}>
            Newer
          </.link>
          <.link :if={@history.older} id="workspace-history-older" patch={@history.older}>
            Older
          </.link>
        </nav>
        <p
          :if={@history.more? and is_nil(@history.older)}
          id="workspace-history-end"
          class="workspace-detail"
        >
          Older commits are in the repository. Fetch it with git to read them.
        </p>
      </section>
    </article>
    """
  end

  attr :files, :any, required: true, doc: "the folder or file as read, or `:unreadable`"

  attr :signed_out?, :boolean,
    default: false,
    doc: "whether nobody is signed in, so the members-only page offers Sign in"

  def files(%{files: :unreadable} = assigns), do: ~H|<.unreadable id="workspace-files-page" />|

  def files(%{files: %{members_only?: true}} = assigns) do
    ~H"""
    <article id="workspace-files-page" class="workspace-page">
      <header class="workspace-heading">
        <h2>Code</h2>
        <p id="workspace-files-members-only" class="workspace-lede">
          This is {@files.fleet_name}’s shared code. Its Key holders and their paired agents can read it.
        </p>
        <.link patch={KeyLinks.members_path(@files.fleet_id)}>See this fleet’s Keys</.link>
        <Regent.Primitives.button
          :if={@signed_out?}
          id="workspace-files-sign-in"
          type="button"
          variant="secondary"
          data-account-target="sign-in"
        >
          Sign in
        </Regent.Primitives.button>
      </header>
    </article>
    """
  end

  def files(assigns) do
    ~H"""
    <article id="workspace-files-page" class="workspace-page">
      <header class="workspace-heading">
        <p class="workspace-kicker">
          <.link patch={"#{Regents.Keyfleet.Fleets.path(@files.fleet_id)}/workspace"}>Workspace</.link>
        </p>
        <h2>{if @files.path == "", do: "Code", else: Path.basename(@files.path)}</h2>
        <p :if={@files.at} id="workspace-files-at" class="workspace-lede">
          At commit
          <.link :if={@files.commit_link} patch={@files.commit_link}><code>{String.slice(
            @files.at,
            0,
            12
          )}</code></.link><code :if={is_nil(@files.commit_link)}>{String.slice(@files.at, 0, 12)}</code>, read-only.
          <.link
            :if={@files.commit_link}
            id="workspace-files-now"
            patch={Regents.Keyfleet.Code.files_path(@files.fleet_id, @files.repository, @files.path)}
          >
            See it as it is now
          </.link>
        </p>
        <nav
          :if={@files.path != ""}
          id="workspace-files-crumbs"
          class="workspace-crumbs"
          aria-label="Folders"
        >
          <.link patch={
            Regents.Keyfleet.Code.files_path(@files.fleet_id, @files.repository, "", @files.at)
          }>
            Code
          </.link>
          <%= for crumb <- @files.crumbs do %>
            <span aria-hidden="true">/</span>
            <.link patch={crumb.link}>{crumb.name}</.link>
          <% end %>
        </nav>
      </header>

      <div class="workspace-item-grid">
        <section
          id="workspace-files"
          class="workspace-panel workspace-wide"
          aria-label={if @files.path == "", do: "Code", else: @files.path}
        >
          <p :if={@files.listing == :unreadable} id="workspace-files-unreadable">
            The code can’t be read right now. Try again in a minute.
          </p>
          <p :if={@files.listing == :removed} id="workspace-files-removed">
            A later change removed this from the code.
            <.link patch={Regents.Keyfleet.Code.files_path(@files.fleet_id, @files.repository, "")}>Open the code</.link>
          </p>
          <.folder
            :if={match?({:folder, _}, @files.listing)}
            listing={@files.listing}
            pinned={@files.pinned}
            project={@files.project}
            active?={@files.active?}
          />
          <.file :if={match?({:file, _}, @files.listing)} listing={@files.listing} />
        </section>

        <section
          :if={@files.clone_url}
          class="workspace-panel"
          aria-labelledby="workspace-files-get-title"
        >
          <h2 id="workspace-files-get-title">Clone</h2>
          <p id="workspace-files-clone"><code>git clone {@files.clone_url}</code></p>
          <.link id="workspace-files-history" class="code-action" patch={@files.history_link}>
            History
          </.link>
        </section>

        <section
          :if={is_nil(@files.at)}
          class="workspace-panel"
          aria-labelledby="workspace-files-pushes-title"
        >
          <h2 id="workspace-files-pushes-title">Pushes</h2>
          <Regent.Primitives.empty_state
            :if={@files.pushes == []}
            id="workspace-files-no-pushes"
            class="kf-empty"
            title="No changes have been sent yet."
          />
          <ol :if={@files.pushes != []} id="workspace-files-pushes" class="workspace-lines">
            <li :for={push <- @files.pushes} data-push={push.id}>
              <p>
                <.key fleet_id={@files.fleet_id} token_id={push.token_id} agent={push.agent} />
                sent {push.what}, ending at <.value value={push.commit} fleet_id={@files.fleet_id} />
              </p>
              <p class="workspace-detail">
                <RegentsWeb.Keyfleet.Time.local
                  id={"workspace-files-push-#{push.id}-at"}
                  at={push.at}
                  as={:clock}
                  title_as={:moment}
                />
              </p>
            </li>
          </ol>
        </section>
      </div>
    </article>
    """
  end

  attr :listing, :any, required: true

  attr :pinned, :map,
    required: true,
    doc: "whose each path pinned in the project's code is, `:mine` or `:theirs`"

  attr :project, :string, required: true
  attr :active?, :boolean, required: true

  defp folder(%{listing: {:folder, entries}} = assigns) do
    assigns = assign(assigns, :entries, entries)

    ~H"""
    <Regent.Primitives.empty_state
      :if={@entries == []}
      id="workspace-files-empty"
      class="kf-empty"
      title="No code has been sent yet."
    />
    <ol :if={@entries != []} id="workspace-file-rows" class="workspace-rows">
      <li
        :for={entry <- @entries}
        class="workspace-row workspace-row--pinnable"
        data-file={entry.name}
      >
        <span class="workspace-kind">{if entry.folder?, do: "Folder", else: "File"}</span>
        <.link class="workspace-row-title" patch={entry.link}>{entry.name}</.link>
        <span :if={entry.size} class="workspace-row-meta">{size(entry.size)}</span>
        <.pin_toggle
          id={"workspace-file-#{entry_id(entry.path)}-pin"}
          place={:code}
          project={@project}
          active?={@active?}
          target={entry.path}
          name={entry.path}
          whose={@pinned[entry.path]}
        />
      </li>
    </ol>
    """
  end

  attr :listing, :any, required: true

  defp file(%{listing: {:file, contents}} = assigns) do
    assigns = assign(assigns, :contents, contents)

    ~H"""
    <p :if={@contents == :too_large} id="workspace-file-too-large">
      This file is too large to show here. Copy the code to read it.
    </p>
    <p :if={@contents == :not_text} id="workspace-file-not-text">
      This file isn’t text, so it isn’t shown here. Copy the code to open it.
    </p>
    <pre :if={is_binary(@contents)} id="workspace-file" class="workspace-file"><code>{@contents}</code></pre>
    """
  end

  attr :board, :map, required: true
  attr :notice, :string, default: nil

  # What the fleet's Keys made public, newest first: for posts, the posts
  # that Key wrote in that range of one room, word for word, each with its
  # writer and when it was written; for an item, the item as it stands; for
  # a saved notebook page, Open, which opens it for anyone and is described
  # by the line above naming it and its project. The Key that made
  # something public takes it back, and a member's Key makes its own posts
  # and saved pages public into the active project on show.
  defp public(assigns) do
    ~H"""
    <section id="workspace-public" class="workspace-public" aria-labelledby="workspace-public-title">
      <header class="workspace-heading">
        <h2 id="workspace-public-title">Public</h2>
        <p class="workspace-lede">Work this fleet’s Keys chose to show everyone, word for word.</p>
      </header>
      <Regent.Primitives.empty_state
        :if={@board.public == []}
        id="workspace-public-empty"
        class="kf-empty"
        title="Nothing public here yet."
      >
        Each Key chooses which of its own work everyone can read.
      </Regent.Primitives.empty_state>
      <article
        :for={record <- @board.public}
        id={"public-#{record.id}"}
        class="workspace-panel workspace-public-record"
        aria-labelledby={"public-#{record.id}-title"}
      >
        <header class="workspace-public-head">
          <p :if={record.kind == :posts} class="workspace-kicker">
            {record.room_label} · posts {record.from} to {record.to}
            <span :if={record.label}>· {record.label}</span>
          </p>
          <p :if={record.kind == :item} class="workspace-kicker">
            {type_label(record.item.type)} <span :if={record.label}>· {record.label}</span>
          </p>
          <p :if={record.kind == :page} id={"public-#{record.id}-kind"} class="workspace-kicker">
            Notebook page <span :if={record.label}>· {record.label}</span>
          </p>
          <p :if={record.kind == :commit} class="workspace-kicker">
            Code <span :if={record.label}>· {record.label}</span>
          </p>
          <h3 :if={record.kind == :posts} id={"public-#{record.id}-title"}>
            {ActivityLines.key_name(record.key, record.agent)}
          </h3>
          <h3 :if={record.kind == :item} id={"public-#{record.id}-title"}>
            {record.item.title || type_label(record.item.type)}
          </h3>
          <h3 :if={record.kind == :page} id={"public-#{record.id}-title"}>
            {ActivityLines.key_name(record.key, nil)}
          </h3>
          <h3 :if={record.kind == :commit} id={"public-#{record.id}-title"}>
            Commit {String.slice(record.commit, 0, 12)}
          </h3>
          <p class="workspace-detail">
            <span :if={record.kind == :posts}>{posts_shown(length(record.posts))} ·</span>
            <span :if={record.kind == :item}>
              Added by <.part part={record.item.by} fleet_id={@board.fleet_id} /> ·
            </span>
            made public
            <RegentsWeb.Keyfleet.Time.local id={"public-#{record.id}-at"} at={record.at} as={:stamp} />
          </p>
          <Regent.Primitives.button
            :if={record.mine?}
            id={"public-#{record.id}-withdraw"}
            type="button"
            variant="secondary"
            phx-click="withdraw_publication"
            phx-value-id={record.id}
          >
            Take back
          </Regent.Primitives.button>
        </header>
        <dl :if={record.kind == :item} id={"public-#{record.id}-fields"} class="workspace-fields">
          <div :for={{label, value} <- record.item.fields}>
            <dt>{label}</dt>
            <dd><.value value={value} fleet_id={@board.fleet_id} /></dd>
          </div>
        </dl>
        <p :if={record.kind == :item} class="workspace-detail">
          Last changed
          <RegentsWeb.Keyfleet.Time.local
            id={"public-#{record.id}-changed-at"}
            at={record.item.changed_at}
            as={:stamp}
          />
        </p>
        <p :if={record.kind == :page}>
          <a
            id={"public-#{record.id}-page"}
            class="workspace-uri"
            href={record.page_url}
            target="_blank"
            rel="noopener noreferrer"
            aria-describedby={"public-#{record.id}-kind"}
          >
            Open
          </a>
        </p>
        <p :if={record.kind == :commit}>
          <.link id={"public-#{record.id}-files"} class="workspace-uri" patch={record.files_url}>
            Browse the files
          </.link>
        </p>
        <ol :if={record.kind == :posts} class="rooms-thread-list workspace-public-posts">
          <li :for={post <- record.posts} id={"public-#{record.id}-#{post.seq}"}>
            <p class="rooms-author">
              <.link patch={KeyLinks.key_path(@board.fleet_id, post.as_key)}>
                {ActivityLines.key_name(post.as_key, nil)}
              </.link>
              <.agent_picture :if={post.author.picture} src={post.author.picture} />
              <RoomsLive.writer id={"public-#{record.id}-#{post.seq}-writer"} author={post.author} />
              <RoomsLive.verified_human :if={post.author.human_backed} />
            </p>
            <p :if={post.reply_to_seq} class="rooms-detail">
              Replying to post {post.reply_to_seq}
            </p>
            <div class="rooms-body">{RoomsLive.body_html(post.body, @board.fleet_id)}</div>
            <p class="rooms-detail">
              Post {post.seq} ·
              <RegentsWeb.Keyfleet.Time.local
                id={"public-#{record.id}-#{post.seq}-at"}
                at={post.inserted_at}
                as={:stamp}
              />
            </p>
          </li>
        </ol>
      </article>
      <nav
        :if={@board.public_more || @board.public_first}
        id="workspace-public-pages"
        class="workspace-pages"
      >
        <.link :if={@board.public_first} id="workspace-public-first" patch={@board.public_first}>
          Newest
        </.link>
        <.link :if={@board.public_more} id="workspace-public-more" patch={@board.public_more}>
          Earlier
        </.link>
      </nav>
      <.publish_posts
        :if={@board.you && @board.project && @board.active? && @board.rooms != []}
        board={@board}
      />
      <p :if={@notice} id="public-notice" class="workspace-notebooks-notice" role="status">
        {@notice}
      </p>
    </section>
    """
  end

  defp posts_shown(1), do: "1 post"
  defp posts_shown(count), do: "#{count} posts"

  attr :board, :map, required: true

  # A member's Key makes public the posts it wrote in one of the fleet's
  # rooms, from one post to another, into the project on show; and a saved
  # notebook page the member made, into the project whose notebook made it.
  defp publish_posts(assigns) do
    ~H"""
    <Regent.Primitives.disclosure id="public-posts" summary="Public posts">
      <form id="public-posts-form" class="workspace-project-form" phx-submit="publish_posts">
        <input type="hidden" name="project" value={@board.project} />
        <label>
          Room
          <select name="room" required>
            <option :for={room <- @board.rooms} value={room.slug}>{room.label}</option>
          </select>
        </label>
        <label>
          First post
          <input
            name="from"
            inputmode="numeric"
            maxlength={BoxLimit.maxlength(longest(:post_number))}
            required
          />
        </label>
        <label>
          Last post
          <input
            name="to"
            inputmode="numeric"
            maxlength={BoxLimit.maxlength(longest(:post_number))}
            required
          />
        </label>
        <p class="workspace-detail">
          Only the posts {ActivityLines.key_name(@board.you.key, nil)} wrote in that range show. The room itself stays with its members.
        </p>
        <Regent.Primitives.button type="submit">
          Make public as {ActivityLines.key_name(@board.you.key, nil)}
        </Regent.Primitives.button>
      </form>
    </Regent.Primitives.disclosure>
    <Regent.Primitives.disclosure id="public-page" summary="Public page">
      <form id="public-page-form" class="workspace-project-form" phx-submit="publish_page">
        <label>
          Page address
          <input
            name="page"
            type="url"
            maxlength={BoxLimit.maxlength(longest(:page_address))}
            required
          />
        </label>
        <p class="workspace-detail">
          Paste the address of a saved page you made. Anyone with the link can then open it, signed in or not; the notebook itself stays with members.
        </p>
        <Regent.Primitives.button type="submit">
          Make public as {ActivityLines.key_name(@board.you.key, nil)}
        </Regent.Primitives.button>
      </form>
    </Regent.Primitives.disclosure>
    """
  end

  attr :place, :atom, default: nil

  defp public_notice(%{place: :public} = assigns) do
    ~H"""
    <p id="workspace-notice" class="workspace-notice" role="note">
      Anyone can read this, signed in or not.
    </p>
    """
  end

  defp public_notice(assigns) do
    ~H"""
    <p id="workspace-notice" class="workspace-notice" role="note">
      Every Key holder can read this. Never put passwords or private data here.
    </p>
    """
  end

  # Only members read the workspace, so the person here is signed in and may
  # pair an agent with Pair New Agent.
  defp unavailable(assigns) do
    ~H"""
    <section id="workspace-unavailable" class="workspace-panel">
      <Regent.Primitives.empty_state class="kf-empty" title="Nothing in this workspace yet.">
        Work shows up here once an agent sets the first goal.
        <:action>
          <Shell.pair_button id="workspace-pair" />
        </:action>
      </Regent.Primitives.empty_state>
    </section>
    """
  end

  attr :board, :map, required: true

  # The first page of one kind of item with none of that kind. A workspace
  # always holds its starting goals, so every other first page has items.
  defp no_cards(%{board: %{filter: filter}} = assigns) do
    assigns =
      assign(assigns,
        title: empty_words(filter),
        everything: WorkspacePage.board_path(assigns.board.fleet_id, %{filter | type: nil})
      )

    ~H"""
    <Regent.Primitives.empty_state id="workspace-empty" class="kf-empty" title={@title}>
      <:action>
        <.link class="rg-button rg-button--secondary" patch={@everything}>
          <span class="rg-button__label">Show everything</span>
        </.link>
      </:action>
    </Regent.Primitives.empty_state>
    """
  end

  attr :id, :string, required: true
  attr :fleet, :map, required: true, doc: "the fleet's id and name"
  attr :signed_out?, :boolean, required: true

  # Anyone who holds none of the fleet's Keys and no shard of one. Someone
  # signed out may hold one, so they are offered Sign in.
  defp members_only(assigns) do
    ~H"""
    <article id={@id} class="workspace-page">
      <header class="workspace-heading">
        <h2>Workspace</h2>
        <p id="workspace-members-only" class="workspace-lede">
          This fleet’s open goals. Key holders and their agents see who has each task, and everything else.
        </p>
        <.link patch={KeyLinks.members_path(@fleet.fleet_id)}>See this fleet’s Keys</.link>
        <Regent.Primitives.button
          :if={@signed_out?}
          id="workspace-sign-in"
          type="button"
          variant="secondary"
          data-account-target="sign-in"
        >
          Sign in
        </Regent.Primitives.button>
      </header>
      <section class="workspace-panel" aria-labelledby="workspace-public-projects-title">
        <h2 id="workspace-public-projects-title">Projects</h2>
        <div
          :for={{project, i} <- Enum.with_index(@fleet.projects)}
          id={"workspace-public-project-#{i}"}
          class="workspace-public-project"
        >
          <h3>{project.title}</h3>
          <p :if={project.goals == []} class="workspace-detail">No goals in progress.</p>
          <ul :if={project.goals != []} class="workspace-lines">
            <li :for={goal <- project.goals}>
              <p>{goal}</p>
            </li>
          </ul>
        </div>
      </section>
      <.tools fleet_id={@fleet.fleet_id} />
    </article>
    """
  end

  attr :fleet_id, :string, required: true

  # What anyone may read of where the fleet's members work.
  defp tools(assigns) do
    ~H"""
    <section class="workspace-tools workspace-panel" aria-labelledby="workspace-tools-title">
      <h2 id="workspace-tools-title">Places</h2>
      <dl class="workspace-tools-list">
        <div>
          <dt>Project <span class="workspace-detail">ActiveGraph</span></dt>
          <dd>Goals, tasks and what changed.</dd>
        </div>
        <div>
          <dt>Docs <span class="workspace-detail">marimo</span></dt>
          <dd>
            {if Regents.Keyfleet.Notebooks.hub?(@fleet_id),
              do: "Notebooks and saved results.",
              else: "Notebooks, not set up here yet."}
          </dd>
        </div>
        <div>
          <dt>Code <span class="workspace-detail">Git</span></dt>
          <dd>One shared Git repository.</dd>
        </div>
        <div>
          <dt>Public <span class="workspace-detail">Open to all</span></dt>
          <dd>
            <.link patch={WorkspacePage.place_path(@fleet_id, :public)}>
              Work its Keys chose to show everyone.
            </.link>
          </dd>
        </div>
      </dl>
      <.agent_guide />
    </section>
    """
  end

  attr :id, :string, required: true

  # Told the way the fleet's own page tells it.
  defp unreadable(assigns) do
    ~H"""
    <article id={@id} class="workspace-page">
      <section id="workspace-unreadable" class="workspace-panel">
        <.load_failed />
      </section>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :key, :atom, required: true, doc: "the field that names a row"
  slot :inner_block, required: true

  # A feed of rows in the order given, each with its time in a column of its own.
  # A row that arrives glides in and the rows below it make room.
  defp feed(assigns) do
    ~H"""
    <ol
      id={@id}
      class="workspace-lines workspace-stream"
      phx-hook="MotionList"
      data-variant={RegentsWeb.Motion.standard("list")}
      data-layout-id={@id}
      data-children="[data-row]"
    >
      <li
        :for={row <- @rows}
        id={"#{@id}-#{Map.fetch!(row, @key)}"}
        data-row
        data-layout-id={"#{@id}-#{Map.fetch!(row, @key)}"}
      >
        {render_slot(@inner_block, row)}
        <p class="workspace-detail">
          <RegentsWeb.Keyfleet.Time.local
            id={"#{@id}-#{Map.fetch!(row, @key)}-at"}
            at={row.at}
            as={:clock}
            title_as={:moment}
          />
        </p>
      </li>
    </ol>
    """
  end

  attr :parts, :list, required: true
  attr :fleet_id, :string, required: true

  # The parts of a line sit side by side with nothing between them.
  defp line(assigns), do: ~H|<.part :for={part <- @parts} part={part} fleet_id={@fleet_id} />|

  attr :part, :any, required: true
  attr :fleet_id, :string, required: true

  defp part(%{part: {:key, _token_id, _agent}} = assigns),
    do: ~H"<.key fleet_id={@fleet_id} token_id={elem(@part, 1)} agent={elem(@part, 2)} />"

  defp part(%{part: {:item, _id, _title}} = assigns),
    do: ~H"<.item_link part={@part} fleet_id={@fleet_id} />"

  defp part(assigns), do: ~H"{@part}"

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :fleet_id, :string, required: true

  # Goals one line each, like a list of pages: the title, then what stands
  # out about it, how many joined and the day it last changed.
  defp goal_rows(assigns) do
    ~H"""
    <ol id={@id} class="workspace-rows">
      <li :for={row <- @rows} class="workspace-row" data-item={row.id} data-type="goal">
        <.link class="workspace-row-title" patch={WorkspacePage.item_path(@fleet_id, row.id)}>
          {row.title}
        </.link>
        <span class="workspace-row-meta">
          <span :if={row.project} class="workspace-project-tag" data-project-label>{row.project}</span>
          <span :if={row.starting?} class="workspace-badge">Starting idea</span>
          <span :if={row.archived?} class="workspace-badge">Archived</span>
          <span :if={row.status}>{row.status}</span>
          <span :if={row.joined > 0}>
            <RegentsWeb.Keyfleet.Components.Count.count
              id={"#{@id}-#{row.id}-joined"}
              value={row.joined}
              one="joined"
              many="joined"
            />
          </span>
          <RegentsWeb.Keyfleet.Time.local id={"#{@id}-#{row.id}-on"} at={row.changed_on} as={:date} />
        </span>
      </li>
    </ol>
    """
  end

  attr :id, :string, default: nil
  attr :branch, :list, required: true
  attr :cascade?, :boolean, default: false, doc: "whether its cards cascade in when first seen"

  # One level of a goal's map: each item a card, cut at two corners and
  # edged in the colour of where it stands, with the items that hang from it
  # under it. A line joins each to the card above; a fork's or a review's
  # line is dashed.
  defp map_branch(assigns) do
    ~H"""
    <ol
      id={@id}
      class="workspace-map-branch"
      phx-hook={@cascade? && "MotionCascade"}
      data-variant={@cascade? && RegentsWeb.Motion.standard("grid")}
    >
      <li
        :for={entry <- @branch}
        data-item={entry.item.id}
        data-tone={entry.item.tone}
        data-via={entry.via}
      >
        <div class="workspace-map-card">
          <p class="workspace-map-top">
            <span class="workspace-kind">
              {entry.item.kind}{if entry.item.owner, do: " · #{entry.item.owner}"}
            </span>
            <span :if={entry.item.standing} class="workspace-map-standing">
              <span class="workspace-graph-mark" aria-hidden="true"></span>{entry.item.standing}
            </span>
          </p>
          <.link class="workspace-map-title" patch={entry.item.path}>{entry.item.title}</.link>
        </div>
        <.map_branch :if={entry.branch != []} branch={entry.branch} />
      </li>
    </ol>
    """
  end

  attr :goal, :map, required: true
  attr :fleet_id, :string, required: true

  # The work around a goal, by where it is kept: the workspace's items as the
  # goal's map, and the notebooks, their saved results and the commits of the
  # fleet's code its tasks and evidence cite. Each card and line opens one of
  # them.
  defp goal_work(assigns) do
    ~H"""
    <section
      id="workspace-goal-map"
      class="workspace-panel workspace-wide workspace-map"
      aria-labelledby="workspace-goal-map-title"
    >
      <header class="workspace-graph-head">
        <h2 id="workspace-goal-map-title">Map</h2>
        <.link id="workspace-goal-graph" class="workspace-toggle" patch={@goal.graph}>
          Open in the Graph view
        </.link>
      </header>
      <Regent.Primitives.empty_state
        :if={@goal.map == []}
        id="workspace-goal-map-empty"
        class="kf-empty"
        title="No work is linked to this goal yet."
      />
      <.map_branch
        :if={@goal.map != []}
        id="workspace-goal-map-items"
        branch={@goal.map}
        cascade?={true}
      />
      <p :if={@goal.more?} id="workspace-goal-map-more" class="workspace-detail">
        The 120 most recently changed.
      </p>
    </section>

    <section
      id="workspace-goal-notebooks"
      class="workspace-panel"
      aria-labelledby="workspace-goal-notebooks-title"
    >
      <h2 id="workspace-goal-notebooks-title">Notebooks</h2>
      <p :if={is_nil(@goal.notebooks)} id="workspace-goal-notebooks-none" class="workspace-detail">
        Notebooks aren’t connected for this fleet yet.
      </p>
      <p :if={@goal.notebooks == :unreadable} id="workspace-goal-notebooks-unreadable">
        The notebooks can’t be read right now. Try again in a minute.
      </p>
      <p
        :if={@goal.notebooks_unshown > 0}
        id="workspace-goal-notebooks-unshown"
        class="workspace-detail"
      >
        {@goal.notebooks_unshown} more not shown.
      </p>
      <Regent.Primitives.empty_state
        :if={@goal.notebooks == [] and @goal.results == []}
        id="workspace-goal-notebooks-empty"
        class="kf-empty"
        title="Nothing here yet."
      />
      <ol
        :if={listed(@goal.notebooks) != [] or @goal.results != []}
        id="workspace-goal-notebook-rows"
        class="workspace-rows"
      >
        <li
          :for={notebook <- listed(@goal.notebooks)}
          class="workspace-row"
          data-notebook={notebook.id}
        >
          <span class="workspace-kind">Notebook</span>
          <a class="workspace-row-title" href={notebook.open}>{notebook.title}</a>
          <span :if={notebook.changed_since_run?} class="workspace-row-meta">
            <.changed_mark />
          </span>
        </li>
        <li :for={result <- @goal.results} class="workspace-row" data-item={result.id}>
          <span class="workspace-kind">Result</span>
          <a
            class="workspace-row-title"
            href={result.uri}
            rel="noopener noreferrer"
            data-notebook-result
          >
            {result.title}
          </a>
          <span class="workspace-row-meta">
            <.link patch={WorkspacePage.item_path(@fleet_id, result.id)}>
              {type_label(result.type)}
            </.link>
            <RegentsWeb.Keyfleet.Time.local
              id={"workspace-goal-result-#{result.id}-on"}
              at={result.changed_on}
              as={:date}
            />
          </span>
        </li>
      </ol>
    </section>

    <section
      id="workspace-goal-code"
      class="workspace-panel"
      aria-labelledby="workspace-goal-code-title"
    >
      <h2 id="workspace-goal-code-title">Code</h2>
      <p class="workspace-detail">
        <.link :if={entries(@goal.code) != []} id="workspace-goal-folder" patch={@goal.folder.link}>
          {@goal.folder.path}
        </.link>
        <code :if={entries(@goal.code) == []} id="workspace-goal-folder-name">
          {@goal.folder.path}
        </code>
      </p>
      <p :if={@goal.code == :unreadable} id="workspace-goal-code-unreadable">
        The code can’t be read right now. Try again in a minute.
      </p>
      <Regent.Primitives.empty_state
        :if={@goal.code == [] and @goal.commits == []}
        id="workspace-goal-code-empty"
        class="kf-empty"
        title="Nothing here yet."
      />
      <ol
        :if={entries(@goal.code) != [] or @goal.commits != []}
        id="workspace-goal-code-rows"
        class="workspace-rows"
      >
        <li :for={entry <- entries(@goal.code)} class="workspace-row" data-file={entry.name}>
          <span class="workspace-kind">{if entry.folder?, do: "Folder", else: "File"}</span>
          <.link class="workspace-row-title" patch={entry.link}>{entry.name}</.link>
          <span :if={entry.size} class="workspace-row-meta">{size(entry.size)}</span>
        </li>
        <li :for={commit <- @goal.commits} class="workspace-row" data-item={commit.id}>
          <span class="workspace-kind">Commit</span>
          <.link class="workspace-row-title" patch={commit.path} data-commit={commit.hash}>
            {commit.title}
          </.link>
          <span class="workspace-row-meta">
            <code>{String.slice(commit.hash, 0, 12)}</code>
            <RegentsWeb.Keyfleet.Time.local
              id={"workspace-goal-commit-#{commit.id}-on"}
              at={commit.changed_on}
              as={:date}
            />
          </span>
        </li>
      </ol>
    </section>
    """
  end

  defp listed(notebooks) when is_list(notebooks), do: notebooks
  defp listed(_none_or_unreadable), do: []

  # Notebooks in no folder first, then each folder by name, newest first in
  # each.
  defp by_folder(notebooks) do
    notebooks
    |> Enum.group_by(& &1.folder)
    |> Enum.sort_by(fn {folder, _notebooks} -> {folder != nil, folder} end)
  end

  defp entries(entries) when is_list(entries), do: entries
  defp entries(:unreadable), do: []

  # A file's size the way a person reads it.
  defp size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  attr :card, :map, required: true
  attr :fleet_id, :string, required: true

  defp card(assigns) do
    ~H"""
    <li
      class="workspace-card"
      data-item={@card.id}
      data-type={@card.type}
      phx-mounted={JS.ignore_attributes(["style"])}
    >
      <p class="workspace-kind">
        <span>{type_label(@card.type)}</span>
        <span :if={@card.project} class="workspace-project-tag" data-project-label>{@card.project}</span>
        <span :if={@card.starting?} class="workspace-badge">Starting idea</span>
        <span :if={@card.archived?} class="workspace-badge">Archived</span>
      </p>
      <h3>
        <.link patch={WorkspacePage.item_path(@fleet_id, @card.id)}>{@card.title}</.link>
      </h3>
      <p :if={@card.gist} class="workspace-gist">{@card.gist}</p>
      <dl :if={@card.facts != []} class="workspace-facts">
        <div :for={{label, value} <- @card.facts}>
          <dt>{label}</dt>
          <dd><.value value={value} fleet_id={@fleet_id} /></dd>
        </div>
      </dl>
      <p class="workspace-detail">
        <span>Added by <.part part={@card.by} fleet_id={@fleet_id} /></span>
        <span>
          Last changed
          <RegentsWeb.Keyfleet.Time.local
            id={"workspace-card-#{@card.id}-changed-at"}
            at={@card.changed_at}
            as={:stamp}
          />
        </span>
      </p>
    </li>
    """
  end

  attr :part, :any, required: true
  attr :fleet_id, :string, required: true

  defp item_link(%{part: {:item, id, title}} = assigns) when is_binary(id) and is_binary(title) do
    assigns = assign(assigns, id: id, title: title)

    ~H|“<.link patch={WorkspacePage.item_path(@fleet_id, @id)} data-item-link={@id}>{@title}</.link>”|
  end

  defp item_link(assigns), do: ~H"an item"

  attr :fleet_id, :string, required: true
  attr :token_id, :integer, required: true
  attr :agent, :string, default: nil

  # A key's profile is named by its number, eighteen digits at most. A key an
  # agent wrote as carries the agent's name: "Ada (Key 1,234)".
  defp key(%{token_id: token_id} = assigns) when token_id in 1..999_999_999_999_999_999,
    do:
      ~H|<.link patch={KeyLinks.key_path(@fleet_id, @token_id)}>{ActivityLines.key_name(@token_id, @agent)}</.link>|

  defp key(assigns), do: ~H|<span>{ActivityLines.key_name(@token_id, @agent)}</span>|

  attr :value, :any, required: true
  attr :fleet_id, :string, required: true

  defp value(%{value: {:link, uri}} = assigns) do
    assigns = assign(assigns, :uri, uri)

    ~H|<a class="workspace-uri" href={@uri} rel="noopener noreferrer nofollow ugc">{@uri}</a>|
  end

  defp value(%{value: {:commit, hash, path}} = assigns) do
    assigns = assign(assigns, hash: hash, path: path)

    ~H|<.link class="workspace-uri" patch={@path} data-commit={@hash}>commit {String.slice(@hash, 0, 12)}</.link>|
  end

  defp value(%{value: {:notebook_result, uri}} = assigns) do
    assigns = assign(assigns, :uri, uri)

    ~H|<a class="workspace-uri" href={@uri} rel="noopener noreferrer" data-notebook-result>Saved notebook result</a>|
  end

  defp value(%{value: {:notebook, path}} = assigns) do
    assigns = assign(assigns, :path, path)

    ~H|<a class="workspace-uri" href={@path} data-notebook>Open the notebook</a>|
  end

  defp value(%{value: {:key, _token_id, _agent}} = assigns),
    do: ~H"<.part part={@value} fleet_id={@fleet_id} />"

  defp value(%{value: {:list, _values}} = assigns) do
    ~H"""
    <ul class="workspace-list">
      <li :for={value <- elem(@value, 1)}><.value value={value} fleet_id={@fleet_id} /></li>
    </ul>
    """
  end

  defp value(assigns), do: ~H|<span class="workspace-text">{@value}</span>|

  defp kinds do
    for type <- WorkspacePage.types(), do: {type, elem(WorkspacePage.type_name(type), 1)}
  end

  defp type_label(type) do
    {singular, _plural} = WorkspacePage.type_name(type)
    String.capitalize(singular)
  end

  attr :public, :map, required: true
  attr :notice, :string, default: nil

  # The item on the Public place: the Key that added it makes it public, and
  # the Key that made it public takes it back.
  defp item_public(assigns) do
    ~H"""
    <section
      :if={@public.id || @public.make? || @notice}
      id="workspace-item-public"
      class="workspace-panel workspace-item-public"
    >
      <p :if={@public.id} class="workspace-detail">
        Everyone can read this item on <.link patch={@public.link}>Public</.link>.
      </p>
      <p :if={@public.make?} class="workspace-detail">
        Show this item to everyone on Public, signed in or not. It stays here as it is.
      </p>
      <Regent.Primitives.button
        :if={@public.make?}
        id="workspace-item-publish"
        type="button"
        phx-click="publish_item"
      >
        Make public
      </Regent.Primitives.button>
      <Regent.Primitives.button
        :if={@public.take_back?}
        id="workspace-item-withdraw"
        type="button"
        variant="secondary"
        phx-click="withdraw_publication"
        phx-value-id={@public.id}
      >
        Take back
      </Regent.Primitives.button>
      <p
        :if={@notice}
        id="workspace-item-public-notice"
        class="workspace-notebooks-notice"
        role="status"
      >
        {@notice}
      </p>
    </section>
    """
  end

  defp item_heading(%{object: %{title: title}}) when is_binary(title), do: title
  defp item_heading(_item), do: "Workspace"

  defp empty_words(%{type: type}) do
    {_singular, plural} = WorkspacePage.type_name(type)
    "No #{String.downcase(plural)} yet."
  end

  @doc """
  A press of a pin on the workspace page on show. A pin names something the
  page lists in the project on show, by its place and `target`, and keeps
  the title the page shows; a press naming anything else changes nothing.
  Unpinning lifts the member's own pin with that project, place and target,
  wherever the page showed it; another member's pin stays. Either way the
  page reads afresh: a member who lost their Key meanwhile sees what they
  may read, and a project archived meanwhile shows it takes no new pins.

  The project presses act as the member's Key (`Regents.Keyfleet.Keys.identity/2`):
  start a project, archive the Key's active one, take over or delete one.
  One that goes moves the page to the project it leaves on show; a refused
  one says why.
  """
  def handle_event("pin", %{"place" => place, "project" => project, "target" => target}, socket) do
    workspace = socket.assigns.workspace

    case shown(workspace, project, Map.get(@pin_places, place), target) do
      nil ->
        {:noreply, socket}

      {place, title, folder?} ->
        %{
          fleet_id: workspace.fleet_id,
          project: project,
          place: place,
          target: target,
          title: title,
          folder?: folder?
        }
        |> Graph.pin(actor: ShellLive.human_actor(socket))
        |> pressed(socket)
    end
  end

  def handle_event(
        "unpin",
        %{"place" => place, "project" => project, "target" => target},
        socket
      )
      when is_map_key(@pin_places, place) do
    actor = ShellLive.human_actor(socket)
    fleet_id = socket.assigns.workspace.fleet_id

    case Graph.pins(fleet_id, @pin_places[place], project, actor: actor) do
      {:ok, pins} ->
        case Enum.find(pins, &(&1.target == target)) do
          nil -> {:noreply, read_workspace(socket)}
          pin -> pin |> Graph.unpin(actor: actor) |> pressed(socket)
        end

      failed ->
        pressed(failed, socket)
    end
  end

  def handle_event("project_start", %{"name" => name, "title" => title}, socket),
    do: hold(socket, &Projects.start_project(&1, &2, name, title, &3))

  def handle_event("project_archive", _params, socket),
    do: hold(socket, &Projects.archive_project/3)

  def handle_event("project_take_over", %{"project" => name}, socket),
    do: hold(socket, &Projects.take_over_project(&1, &2, name, &3))

  def handle_event("project_delete", %{"project" => name}, socket),
    do: hold(socket, &Projects.delete_project(&1, &2, name, &3))

  def handle_event("project_show", %{"project" => name, "shown" => shown}, socket),
    do: hold(socket, &Projects.show_project(&1, &2, name, shown == "true", &3))

  def handle_event("project_describe", %{"project" => name, "description" => line}, socket),
    do: hold(socket, &Projects.describe_project(&1, &2, name, line, &3))

  def handle_event(
        "publish_posts",
        %{"project" => project, "room" => room, "from" => from, "to" => to},
        socket
      ) do
    with {from, ""} <- post_number(from),
         {to, ""} <- post_number(to) do
      publish(socket, &Projects.publish_posts(&1, &2, project, room, from, to, &3))
    else
      :too_long ->
        {:noreply, assign(socket, :publish_notice, "That post number is too long.")}

      _not_numbers ->
        {:noreply, assign(socket, :publish_notice, "Post numbers are whole numbers from 1.")}
    end
  end

  def handle_event("publish_item", _params, socket) do
    item = socket.assigns.workspace.object.id
    publish(socket, &Projects.publish_item(&1, &2, item, &3))
  end

  def handle_event("publish_page", %{"page" => page}, socket) do
    if BoxLimit.too_long?(page, longest(:page_address)),
      do:
        {:noreply,
         assign(
           socket,
           :publish_notice,
           "A page address is at most #{longest(:page_address)} characters."
         )},
      else: publish(socket, &Projects.publish_page(&1, &2, String.trim(page), &3))
  end

  def handle_event("publish_commit", _params, socket) do
    %{project: project, hash: hash} = socket.assigns.workspace
    publish(socket, &Projects.publish_commit(&1, &2, project, hash, &3))
  end

  def handle_event("withdraw_publication", %{"id" => id}, socket),
    do: publish(socket, &Projects.withdraw_publication(&1, &2, id, &3))

  def handle_event(
        "notebook_lock",
        %{"project" => project, "notebook" => notebook_id, "locked" => locked},
        socket
      )
      when locked in ["true", "false"] do
    notebook(socket, fn fleet_id, actor ->
      with {:ok, _lock} <-
             Notebooks.lock(
               fleet_id,
               actor,
               Notebooks.subject(actor),
               project,
               notebook_id,
               locked == "true"
             ),
           do: {:ok, nil}
    end)
  end

  def handle_event("notebook_restore", %{"project" => project, "copy" => copy_id}, socket) do
    notebook(socket, fn fleet_id, actor ->
      with {:ok, %{title: title}} <-
             Notebooks.restore(fleet_id, actor, Notebooks.subject(actor), project, copy_id),
           do: {:ok, "Brought back as #{title}."}
    end)
  end

  def handle_event(_press, _params, socket), do: {:noreply, socket}

  defp hold(socket, step) do
    actor = ShellLive.human_actor(socket)
    %{fleet_id: fleet_id} = board = socket.assigns.workspace

    with %{token_id: key} <- Keys.identity(actor, fleet_id),
         {:ok, project} <- step.(fleet_id, key, actor: actor) do
      on_show = if project.state == :deleted, do: nil, else: project.name

      # As the picker does, so a press in the Project's graph stays in it.
      {:noreply, Phoenix.LiveView.push_patch(socket, to: picker_path(board, on_show))}
    else
      nil ->
        {:noreply, assign(socket, :project_notice, refusal(%NotKeyHolderError{}))}

      {:error, error} ->
        {:noreply, socket |> assign(:project_notice, refused(error)) |> read_workspace()}
    end
  end

  # The longest value the public forms' boxes take (`RegentsWeb.Keyfleet.BoxLimit`):
  # room for any post's number, and a page address as the signed API takes it.
  defp longest(:post_number), do: 20
  defp longest(:page_address), do: 512

  # A post number as typed: `:too_long` past its box's rule, read otherwise.
  defp post_number(typed) do
    if BoxLimit.too_long?(typed, longest(:post_number)),
      do: :too_long,
      else: Integer.parse(typed)
  end

  # Making posts public, or taking them back, acts as the member's Key; the
  # page reads afresh either way.
  defp publish(socket, step) do
    actor = ShellLive.human_actor(socket)
    fleet_id = socket.assigns.workspace.fleet_id

    notice =
      with %{token_id: key} <- Keys.identity(actor, fleet_id),
           {:ok, _publication} <- step.(fleet_id, key, actor: actor) do
        nil
      else
        nil -> refusal(%NotKeyHolderError{})
        {:error, error} -> refused(error)
      end

    {:noreply, socket |> assign(:publish_notice, notice) |> read_workspace()}
  end

  # A notebook press acts as the signed-in member; the page reads afresh
  # either way and says how it went.
  defp notebook(socket, step) do
    notice =
      case ShellLive.human_actor(socket) do
        %Human{} = actor ->
          case step.(socket.assigns.workspace.fleet_id, actor) do
            {:ok, notice} -> notice
            {:error, reason} -> notebook_refusal(reason)
          end

        nil ->
          "Sign in to change this fleet’s notebooks."
      end

    {:noreply, socket |> assign(:notebooks_notice, notice) |> read_workspace()}
  end

  defp notebook_refusal(:not_maker),
    do: "Only whoever made this notebook locks, unlocks or brings it back."

  defp notebook_refusal(:not_holder),
    do: "Only holders of this fleet’s Keys change its notebooks."

  defp notebook_refusal(:edits_restricted), do: "A vote has stopped this Key’s edits for now."

  defp notebook_refusal(:setting_up),
    do: "This project’s notebooks are still being set up. Try again in a few minutes."

  defp notebook_refusal(%ClosedError{} = closed), do: Exception.message(closed)

  defp notebook_refusal(reason) when reason in [:not_found, :copy_not_found, :file_not_found],
    do: "That notebook or copy is gone now."

  defp notebook_refusal(_reason),
    do: "The notebooks aren’t answering right now. Try again in a moment."

  defp refused(%{errors: errors}),
    do: Enum.find_value(errors, &refusal/1) || "That didn’t go through. Try again in a minute."

  defp refusal(%HoldError{words: words}), do: words
  defp refusal(%PublishError{words: words}), do: words
  defp refusal(%NameTakenError{} = error), do: Exception.message(error)
  defp refusal(%{field: :name}), do: "A short name is lowercase letters, digits and hyphens."
  defp refusal(%{field: :title}), do: "A title is 1 to 60 characters."

  # A post range's own rules: from 1, and no larger than a post's number can be.
  defp refusal(%InvalidArgument{field: field, value: value})
       when field in [:from_seq, :to_seq] and is_integer(value) and value >= 1,
       do: "No post has that number."

  defp refusal(%InvalidArgument{field: field}) when field in [:from_seq, :to_seq],
    do: "Post numbers are whole numbers from 1."

  defp refusal(%NotKeyHolderError{}),
    do: "Only holders of this fleet’s Keys work on its projects."

  defp refusal(%EditsRestrictedError{}), do: "A vote has stopped this Key’s edits for now."

  defp refusal(%OwnershipRefreshingError{}),
    do: "Key holders are being checked. Try again in a minute."

  defp refusal(_error), do: nil

  # What the page lists in a place of the project on show under `target`:
  # its title, and whether it is a folder.
  defp shown(%{place: :docs, project: project, notebooks: notebooks}, project, :docs, target) do
    notebooks
    |> listed()
    |> Enum.find_value(&(&1.id == target && {:docs, &1.title, false}))
  end

  defp shown(%{place: :code, project: project, files: files}, project, :code, target),
    do: shown_file(entries(files), target)

  defp shown(%{project: project, listing: {:folder, entries}}, project, :code, target),
    do: shown_file(entries, target)

  defp shown(_workspace, _project, _place, _target), do: nil

  defp shown_file(entries, target),
    do: Enum.find_value(entries, &(&1.path == target && {:code, &1.path, &1.folder?}))

  defp pressed(:ok, socket), do: {:noreply, read_workspace(socket)}
  defp pressed({:ok, _pin}, socket), do: {:noreply, read_workspace(socket)}
  # A pin that isn't the member's, or that they lifted already from another
  # tab; or one in a project archived meanwhile.
  defp pressed({:error, %Ash.Error.Forbidden{}}, socket), do: {:noreply, read_workspace(socket)}
  defp pressed({:error, %Ash.Error.Invalid{}}, socket), do: {:noreply, read_workspace(socket)}

  defp pressed({:error, failure}, _socket), do: raise(failure)

  @doc """
  A wait begun for a workspace the page has since left reads nothing. A read
  again that fails keeps what the page shows; the next notice reads again. A
  file or folder a later change took out of the code says it was removed.
  """
  def handle_info(:refresh_workspace, %{assigns: %{workspace: %{}}} = socket) do
    socket = assign(socket, :workspace_refresh?, false)

    case PageRead.run("workspace", fn -> workspace(socket) end) do
      {:ok, workspace} -> {:noreply, assign(socket, :workspace, workspace)}
      {:error, _failure} -> {:noreply, socket}
    end
  rescue
    failure in RegentsWeb.NotFoundError ->
      socket = assign(socket, :workspace_refresh?, false)
      {:noreply, removed(socket, failure, __STACKTRACE__)}
  end

  def handle_info(:refresh_workspace, socket),
    do: {:noreply, assign(socket, :workspace_refresh?, false)}

  # Only a code page's file or folder can go while the page is open.
  defp removed(%{assigns: %{route_spec: %{route_id: :code_files}}} = socket, _failure, _trace),
    do: update(socket, :workspace, &Map.put(&1, :listing, :removed))

  defp removed(_socket, failure, trace), do: reraise(failure, trace)

  @doc "One read, a moment later, when the log has moved past what the page last read."
  def refresh_soon(socket, seen, run_id, watermark) do
    if moved?(seen, run_id, watermark), do: refresh_later(socket), else: socket
  end

  @doc "One read, a moment later, answering every notice that comes meanwhile."
  def refresh_later(socket) do
    if socket.assigns.workspace_refresh? do
      socket
    else
      Process.send_after(self(), :refresh_workspace, @workspace_refresh_after)
      assign(socket, :workspace_refresh?, true)
    end
  end

  @doc """
  The workspace page the address names, read afresh; or `:unreadable` when the
  database couldn't be read.
  """
  def read_workspace(socket) do
    case PageRead.run("workspace", fn -> workspace(socket) end) do
      {:ok, workspace} -> assign(socket, :workspace, workspace)
      {:error, _failure} -> assign(socket, :workspace, :unreadable)
    end
  end

  defp workspace(%{assigns: %{route_spec: %{route_id: :workspace}}} = socket) do
    params = socket.assigns.workspace_params
    WorkspacePage.board(params["fleet_id"], params, ShellLive.human_actor(socket))
  end

  defp workspace(%{assigns: %{route_spec: %{route_id: :workspace_item}}} = socket) do
    params = socket.assigns.workspace_params

    WorkspacePage.item(
      params["fleet_id"],
      params["object_id"],
      params,
      ShellLive.human_actor(socket)
    )
  end

  defp workspace(%{assigns: %{route_spec: %{route_id: :code_commit}}} = socket) do
    params = socket.assigns.workspace_params

    WorkspacePage.commit(
      params["fleet_id"],
      params["repository"],
      params["commit"],
      ShellLive.human_actor(socket)
    )
  end

  defp workspace(%{assigns: %{route_spec: %{route_id: :code_history}}} = socket) do
    params = socket.assigns.workspace_params

    WorkspacePage.history(
      params["fleet_id"],
      params["repository"],
      params["from"],
      WorkspacePage.history_page_number!(params["page"]),
      ShellLive.human_actor(socket)
    )
  end

  defp workspace(%{assigns: %{route_spec: %{route_id: :code_files}}} = socket) do
    params = socket.assigns.workspace_params

    WorkspacePage.files(
      params["fleet_id"],
      params["repository"],
      params,
      ShellLive.human_actor(socket)
    )
  end

  # A copy of another log, or a place further on in the same one.
  defp moved?({run_id, seen_seq}, run_id, watermark), do: watermark > seen_seq
  defp moved?(_seen, _run_id, _watermark), do: true
end
