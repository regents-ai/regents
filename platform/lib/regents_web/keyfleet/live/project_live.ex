defmodule RegentsWeb.Keyfleet.ProjectLive do
  @moduledoc """
  A project's page (`RegentsWeb.Keyfleet.ProjectPage`): its title, fleet and Key, the
  line its Key describes it with, its goals, a "Bring your agent" link that
  pairs a visitor's agent and sends it here, and, when the Key holding it shows its work to everyone, its latest
  work, what it produced and the tasks nobody has joined yet or blocked, each with the
  agent and Key that made it, and under each goal the tasks that deliver on
  it. Each open or blocked task has its own "Bring your agent" link. For a
  reader who may read the workspace each title opens its item there, a part
  with more than it lists links to the project there, and so does "Open in
  the workspace"; anyone else reads plain titles and no workspace links.
  """
  use RegentsWeb, :html
  import RegentsWeb.Components.PageHead, only: [page_head: 1]

  alias Regents.Keyfleet.Fleets.Presets
  alias RegentsWeb.Keyfleet.ActivityLines

  attr :project, :map, required: true

  attr :workspace?, :boolean,
    required: true,
    doc: "the reader may open its items in the workspace"

  def page(assigns) do
    ~H"""
    <article id="project-page" class="project-page" data-project={@project.name}>
      <p class="project-kicker">
        <.link patch={@project.fleet_path}>{@project.fleet_name}</.link>
        · <.link patch={"#{@project.fleet_path}/workspace"}>Workspace</.link>
      </p>
      <.page_head title={@project.title} />
      <p id="project-held" class="project-held">
        {held_by(@project)} · <a href={@project.fleet_path}>{@project.fleet_name}</a>
      </p>
      <p :if={@project.description} id="project-description" class="project-description">
        {@project.description}
      </p>

      <p id="project-actions" class="project-actions">
        <Regent.Primitives.button
          :if={not @workspace? and not Presets.given?(@project.fleet_id)}
          id="project-buy-key"
          type="button"
          variant="primary"
          phx-click="open_buy_key"
          phx-value-fleet={@project.fleet_id}
          aria-haspopup="dialog"
        >
          Buy Key
        </Regent.Primitives.button>
        <.link
          id="project-bring-agent"
          href={@project.pair_path}
          class={[
            "rg-button",
            if(not @workspace? and not Presets.given?(@project.fleet_id),
              do: "rg-button--secondary",
              else: "rg-button--primary"
            )
          ]}
        >
          <span class="rg-button__label">Bring your agent</span>
        </.link>
        <.link
          :if={@workspace?}
          id="project-workspace"
          navigate={@project.workspace_path}
          class="project-workspace"
        >
          Open in the workspace
        </.link>
        <.link
          :if={@project.public_path}
          id="project-public"
          navigate={@project.public_path}
          class="project-workspace"
        >
          Read its public record
        </.link>
      </p>

      <section
        :if={@project.demonstrations != []}
        id="project-demonstrations"
        class="project-part project-demonstrations"
        aria-labelledby="project-demonstrations-title"
      >
        <h2 id="project-demonstrations-title">
          Demonstrations <span class="project-count">{length(@project.demonstrations)}</span>
        </h2>
        <p class="project-demo-note">
          Saved notebook runs made public by a Key. Opens as a static snapshot with no sign-in; live marimo notebooks stay members-only.
        </p>
        <ul class="project-items">
          <li :for={demo <- @project.demonstrations} id={"project-demo-#{demo.id}"}>
            <div class="project-item">
              <span class="project-type">Saved run</span>
              <span class="project-title">{demo.key}</span>
              <span class="project-by">
                Published
                <RegentsWeb.Keyfleet.Time.local
                  id={"project-demo-#{demo.id}-at"}
                  at={demo.at}
                  as={:stamp}
                />
              </span>
            </div>
            <a
              id={"project-demo-#{demo.id}-open"}
              href={demo.page_url}
              target="_blank"
              rel="noopener noreferrer"
              class="rg-button rg-button--secondary project-demo-open"
            >
              <span class="rg-button__label">View demonstration</span>
            </a>
          </li>
        </ul>
      </section>

      <section
        :if={@project.goals}
        id="project-goals"
        class="project-part"
        aria-labelledby="project-goals-title"
      >
        <h2 id="project-goals-title">Goals</h2>
        <ul :if={@project.goals != []} class="project-items">
          <li :for={goal <- @project.goals}><span class="project-title">{goal}</span></li>
        </ul>
        <p :if={@project.goals == []} class="project-empty">No open goals yet.</p>
        <p id="project-members-only" class="project-note">
          <span :if={@project.demonstrations == []}>No public demonstrations published yet.</span>
          Full workspace tasks, live marimo notebooks, and member chat are for the fleet's Key holders.
        </p>
      </section>

      <div :if={@project.parts} id="project-parts" class="project-parts">
        <.part
          workspace?={@workspace?}
          id="project-goals"
          title="Goals"
          labelled={false}
          part={@project.parts.goals}
          more={@project.workspace_path}
          empty="No open goals yet."
        />
        <.part
          workspace?={@workspace?}
          id="project-work"
          title="Recent Work"
          part={@project.parts.work}
          more={@project.workspace_path}
          empty="No work yet."
        />
        <.part
          workspace?={@workspace?}
          id="project-outputs"
          title="Outputs"
          part={@project.parts.outputs}
          more={@project.workspace_path}
          empty="No findings or accepted tasks yet."
        />
        <.part
          workspace?={@workspace?}
          id="project-open"
          title="Open tasks"
          labelled={false}
          invites
          part={@project.parts.open}
          more={@project.workspace_path}
          empty="No open tasks."
        />
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :part, :map, required: true
  attr :more, :string, required: true, doc: "where the rest of a part is read"
  attr :empty, :string, required: true

  attr :labelled, :boolean,
    default: true,
    doc: "false where every row has the same type and standing"

  attr :invites, :boolean,
    default: false,
    doc: "each task has a link that pairs a visitor's agent and sends it there"

  attr :workspace?, :boolean, required: true, doc: "each title opens its item in the workspace"

  defp part(assigns) do
    ~H"""
    <section id={@id} class="project-part" aria-labelledby={"#{@id}-title"}>
      <h2 id={"#{@id}-title"}>{@title} <span class="project-count">{@part.count}</span></h2>
      <ul :if={@part.items != []} class="project-items">
        <li :for={item <- @part.items} data-item={item.id}>
          <div class="project-item">
            <span :if={@labelled} class="project-type">{item.type}</span>
            <span :if={@invites and item.blocked?} class="project-type project-help">
              Needs help
            </span>
            <.link :if={@workspace?} navigate={item.path} class="project-title">
              {item.title}
            </.link>
            <span :if={not @workspace?} class="project-title">{item.title}</span>
            <span class="project-by">{item.by}</span>
          </div>
          <span :if={@labelled and item.standing} class="project-standing">{item.standing}</span>
          <ul
            :if={item.tasks != []}
            class="project-goal-tasks"
            aria-label={"Tasks for " <> item.title}
          >
            <li :for={task <- item.tasks} data-item={task.id}>
              <.link :if={@workspace?} navigate={task.path}>{task.title}</.link>
              <span :if={not @workspace?}>{task.title}</span>
              <span :if={task.standing} class="project-standing">{task.standing}</span>
            </li>
          </ul>
          <.link
            :if={@invites}
            href={item.pair_path}
            class="project-invite"
            aria-label={"Bring your agent to " <> item.title}
          >
            Bring your agent
          </.link>
        </li>
      </ul>
      <p :if={@part.items == []} class="project-empty">{@empty}</p>
      <.link :if={@workspace? and @part.more?} navigate={@more} class="project-more">
        See all
      </.link>
    </section>
    """
  end

  defp held_by(%{key: nil}), do: "Shared by the whole fleet"
  defp held_by(%{key: key}), do: "Held by " <> ActivityLines.key_name(key, nil)
end
