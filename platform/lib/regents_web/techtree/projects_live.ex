defmodule RegentsWeb.Techtree.ProjectsLive do
  @moduledoc """
  The account's Projects: the work Techtree's team delivered to the person
  (`Regents.Techtree.Projects.Project`), listed newest first at
  `/techtree/account/projects`, and each project's page at
  `/techtree/account/projects/:id`.

  A project's page says what the work found, in plain words: the verdict and
  the success the customer agreed to; the original against the selected Skill
  on the final test, as figures and as two bars measured against the pass
  bar; each case, with those that got worse marked; the candidates tried; how
  the work was set up; the report; and the package to download. Everything it
  shows comes from the project's manifest, checked when the team delivered it
  on techtree.sh.

  Only a signed-in person's own projects are read: a project that is someone
  else's, was withdrawn or never was is the not-found page. Signed out, the page
  reads nothing and offers the site's sign-in, which opens this same address
  again signed in. Each read the open page makes, as it connects and on each
  move between the list and a project, spends one of its address's
  `:techtree_project_reads` (`Regents.Limits`); past it, or when the database
  can't be read (`RegentsWeb.Techtree.Outage`), the page says the projects
  couldn't be read.
  """

  use RegentsWeb, :live_view

  import Phoenix.HTML, only: [raw: 1]
  import RegentsWeb.Techtree.Components.Marketing, only: [opening: 1]

  alias Regent.Primitives
  alias Regents.Limits
  alias Regents.Techtree.Projects
  alias RegentsWeb.Account.Identity
  alias RegentsWeb.Techtree.{Layouts, Outage, Services}

  # A difference this unlikely to come from chance alone is beyond chance.
  @beyond_chance 0.05

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign(socket, client_tag: Map.fetch!(session, "client_tag"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, page_title: "Projects", projects: nil, project: nil)

    case Identity.human_actor(socket) do
      nil -> {:noreply, socket}
      actor -> {:noreply, load(socket, socket.assigns.live_action, actor, params)}
    end
  end

  defp load(socket, :index, actor, _params), do: assign(socket, projects: projects(socket, actor))

  # A project is read for its owner only, so one that is someone else's, or
  # was withdrawn, is the not-found page, as a project that never was.
  defp load(socket, :show, actor, %{"id" => id}) do
    case project(socket, actor, id) do
      nil -> raise RegentsWeb.NotFoundError, "no project of yours has that id"
      :unreadable -> assign(socket, project: :unreadable)
      project -> assign(socket, project: project, page_title: project.title)
    end
  end

  defp projects(socket, actor) do
    with :ok <- admit(socket),
         {:ok, projects} <- Outage.read(fn -> Projects.list_my_projects!(actor: actor) end) do
      projects
    else
      _limited_or_down -> :unreadable
    end
  end

  # The address's id is read only as a UUID; anything else is no project.
  defp project(socket, actor, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         :ok <- admit(socket),
         {:ok, project} <- Outage.read(fn -> Projects.get_my_project!(id, actor: actor) end) do
      project
    else
      :error -> nil
      _limited_or_down -> :unreadable
    end
  end

  # The visit's own request is counted with the address's reads of the site.
  # Every read the open page makes after it spends one of the projects' own.
  defp admit(socket) do
    if connected?(socket),
      do: Limits.spend(:techtree_project_reads, socket.assigns.client_tag),
      else: :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page wide flush>
      <div id="account-shell" class="account-shell">
        <.opening
          eyebrow="Account"
          title="Projects"
          line="The work our team delivered to you."
          rise={false}
          book_call={false}
        />
        <div id="route-content" class="account-shell__body">
          <article
            id={if @live_action == :index, do: "projects-page", else: "project-page"}
            class="account-page rg-utility project-page"
          >
            <Regent.Account.signed_out
              :if={not Identity.authenticated?(@access_context)}
              id={
                if @live_action == :index,
                  do: "projects-page-signed-out",
                  else: "project-page-signed-out"
              }
              reason={@signed_out_reason}
            >
              <:sign_in>
                <Primitives.button type="button" data-account-target="sign-in">
                  Sign in
                </Primitives.button>
              </:sign_in>
            </Regent.Account.signed_out>
            <.list
              :if={Identity.authenticated?(@access_context) and @live_action == :index}
              projects={@projects}
            />
            <.show
              :if={Identity.authenticated?(@access_context) and @live_action == :show}
              project={@project}
            />
          </article>
        </div>
      </div>
    </Layouts.page>
    """
  end

  attr :projects, :any, required: true, doc: "the person's projects, or :unreadable"

  defp list(assigns) do
    ~H"""
    <Primitives.notice :if={@projects == :unreadable} tone="error">
      Your projects couldn’t be read. Refresh the page to try again.
    </Primitives.notice>
    <Primitives.empty_state
      :if={@projects == []}
      id="projects-empty"
      title="No projects"
      class="account-panel"
    >
      When our team finishes work for you, it shows here, to read and to download.
      <:action>
        <ul class="project-services" aria-label="Services">
          <li :for={service <- Services.all()}>
            <.link navigate={Services.path(service.id)}>{service.name}</.link>
          </li>
        </ul>
      </:action>
    </Primitives.empty_state>
    <ol :if={is_list(@projects) and @projects != []} id="projects-list" class="project-list">
      <li :for={project <- @projects} id={"project-#{project.id}"}>
        <.link patch={~p"/techtree/account/projects/#{project.id}"} class="project-list__link">
          <span class="project-list__title">{project.title}</span>
          <span class="project-list__meta">
            {Services.fetch!(project.line).name} · <.day at={project.delivered_at} />
          </span>
        </.link>
        <.verdict verdict={project.verdict} />
      </li>
    </ol>
    """
  end

  attr :project, :any, required: true, doc: "the project, read for its owner, or :unreadable"

  defp show(assigns) do
    ~H"""
    <Primitives.notice :if={@project == :unreadable} tone="error">
      This project couldn’t be read. Refresh the page to try again.
    </Primitives.notice>
    <.project :if={is_map(@project)} project={@project} />
    """
  end

  attr :project, :map, required: true

  # @report is the package's Markdown rendered with raw HTML left out and only
  # https addresses kept (report_html/1).
  # sobelow_skip ["XSS.Raw"]
  defp project(assigns) do
    manifest = assigns.project.manifest
    summary = manifest["summary"]

    assigns =
      assign(assigns,
        manifest: manifest,
        summary: summary,
        original: summary["original"],
        selected: summary["selected"],
        report: report_html(assigns.project.report_md)
      )

    ~H"""
    <header class="project-head">
      <.link patch={~p"/techtree/account/projects"} class="project-head__back">Projects</.link>
      <h2 id="project-title">{@project.title}</h2>
      <p class="project-head__meta">
        {Services.fetch!(@project.line).name} · Delivered <.day at={@project.delivered_at} />
      </p>
    </header>

    <section class="account-panel project-verdict" aria-labelledby="project-verdict-title">
      <div class="project-verdict__head">
        <h2 id="project-verdict-title">Verdict</h2>
        <.verdict verdict={@project.verdict} />
      </div>
      <p>{verdict_line(@project.line, @project.verdict)}</p>
      <dl class="project-facts">
        <div>
          <dt>Goal</dt>
          <dd class="project-goal">{@manifest["success"]}</dd>
        </div>
      </dl>
    </section>

    <section
      :if={@project.line == :skills}
      class="account-panel"
      aria-labelledby="project-comparison-title"
    >
      <h2 id="project-comparison-title">Comparison</h2>
      <p class="project-note">
        The original Skill and the selected one on the final test: {count(
          @summary["final_cases"],
          "case",
          "cases"
        )}, each run {count(@summary["repeats"], "time", "times")}.
      </p>
      <div class="project-meters" style={"--pass-bar: #{percent(@summary["pass_bar"])}%"}>
        <.meter id="project-before" label="Before" counts={@original} tone="before" />
        <.meter id="project-after" label="After" counts={@selected} tone="after" />
        <p class="project-meters__legend project-note" aria-hidden="true">
          <span class="project-meters__tick"></span> Pass bar
        </p>
      </div>
      <dl class="project-facts project-facts--row">
        <div>
          <dt>Difference</dt>
          <dd>{difference(@summary["difference"])}</dd>
        </div>
        <div>
          <dt>Certainty</dt>
          <dd>{chance(@summary["p_value"])}</dd>
        </div>
        <div>
          <dt>Pass bar</dt>
          <dd>
            {percent(@summary["pass_bar"])}%, {if @summary["pass_bar_met"],
              do: "met",
              else: "not met"}
          </dd>
        </div>
        <div>
          <dt>Worse</dt>
          <dd>{worse(@summary["regressions"])}</dd>
        </div>
      </dl>
    </section>

    <section class="account-panel project-download" aria-labelledby="project-download-title">
      <h2 id="project-download-title">Download</h2>
      <p>{package_contents(@project.line)}</p>
      <div class="project-download__action">
        <a
          id="project-download"
          href={~p"/techtree/account/projects/#{@project.id}/package"}
          class="rg-button rg-button--primary"
          download
        >
          <span class="rg-button__label">Download</span>
        </a>
        <span class="project-note">{size(@project.package_size)}</span>
      </div>
      <dl class="project-facts">
        <div>
          <dt>Checksum</dt>
          <dd class="project-checksum">
            <code id="project-checksum">{@project.package_sha256}</code>
            <Primitives.copy_icon
              id="project-checksum-copy"
              text={@project.package_sha256}
              label="Copy the checksum"
            />
          </dd>
        </div>
      </dl>
      <p class="project-note">The checksum is the file’s SHA-256, to check the download.</p>
    </section>

    <section
      :if={@project.line == :skills}
      class="account-panel"
      aria-labelledby="project-cases-title"
    >
      <h2 id="project-cases-title">Cases</h2>
      <div
        class="project-table"
        role="region"
        aria-labelledby="project-cases-title"
        tabindex="0"
      >
        <table id="project-cases">
          <thead>
            <tr>
              <th scope="col">Case</th>
              <th scope="col">Before</th>
              <th scope="col">After</th>
              <th scope="col">Change</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={item <- @manifest["cases"]}
              data-change={change(item["original_solved"], item["selected_solved"])}
            >
              <th scope="row"><bdi>{item["id"]}</bdi></th>
              <td>{item["original_solved"]} of {item["repeats"]}</td>
              <td>{item["selected_solved"]} of {item["repeats"]}</td>
              <td>
                <.change change={change(item["original_solved"], item["selected_solved"])} />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section
      :if={@project.line == :skills}
      class="account-panel"
      aria-labelledby="project-candidates-title"
    >
      <h2 id="project-candidates-title">Candidates</h2>
      <div class="project-table" role="region" aria-labelledby="project-candidates-title" tabindex="0">
        <table id="project-candidates">
          <thead>
            <tr>
              <th scope="col">Candidate</th>
              <th scope="col">Solved</th>
              <th scope="col">Outcome</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={candidate <- @manifest["selection"]}>
              <th scope="row">{candidate_name(candidate["candidate"])}</th>
              <td>{candidate["solved"]} of {candidate["attempts"]}</td>
              <td><.outcome candidate={candidate} /></td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section
      :if={@project.line == :skills}
      class="account-panel account-details"
      aria-labelledby="project-setup-title"
    >
      <h2 id="project-setup-title">Setup</h2>
      <dl>
        <div>
          <dt>Model</dt>
          <dd><bdi>{@manifest["setup"]["model"]}</bdi></dd>
        </div>
        <div :if={@manifest["setup"]["tools"] != []}>
          <dt>Tools</dt>
          <dd>
            <ul class="project-plain-list">
              <li :for={tool <- @manifest["setup"]["tools"]}>
                {Services.label(%{maker: tool["maker"], name: tool["name"]})}
                <span class="project-note">{tool["version"]}</span>
              </li>
            </ul>
          </dd>
        </div>
        <div :if={@manifest["setup"]["limits"] != %{}}>
          <dt>Settings</dt>
          <dd>
            <ul class="project-plain-list">
              <li :for={{name, value} <- Enum.sort(@manifest["setup"]["limits"])}>
                {setting(name, value)}
              </li>
            </ul>
          </dd>
        </div>
        <div>
          <dt>Split</dt>
          <dd>{split(@manifest["setup"]["split"])}</dd>
        </div>
      </dl>
    </section>

    <section class="account-panel" aria-labelledby="project-report-title">
      <h2 id="project-report-title">Report</h2>
      <div id="project-report" class="docs-prose project-report">{raw(@report)}</div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :counts, :map, required: true
  attr :tone, :string, required: true

  # One row: its name, its bar against the pass bar, and its figures as text.
  defp meter(assigns) do
    assigns = assign(assigns, share: share(assigns.counts))

    ~H"""
    <div id={@id} class={["project-meter", "project-meter--#{@tone}"]}>
      <span class="project-meter__label">{@label}</span>
      <span class="project-meter__track" aria-hidden="true">
        <span class="project-meter__fill" style={"inline-size: #{@share}%"}></span>
      </span>
      <span class="project-meter__figure">
        {@counts["solved"]} of {@counts["attempts"]}
        <span class="project-note">{round(@share)}%</span>
      </span>
    </div>
    """
  end

  attr :verdict, :atom, required: true

  # A project's verdict as a calm status.
  defp verdict(assigns) do
    ~H"""
    <Primitives.status tone={verdict_tone(@verdict)} class="project-verdict__status">
      {verdict_name(@verdict)}
    </Primitives.status>
    """
  end

  attr :change, :string, required: true

  defp change(assigns) do
    ~H"""
    <Primitives.status :if={@change == "worse"} tone="warning">Worse</Primitives.status>
    <Primitives.status :if={@change == "better"} tone="success">Better</Primitives.status>
    <span :if={@change == "same"} class="project-note">Same</span>
    """
  end

  attr :candidate, :map, required: true

  defp outcome(assigns) do
    ~H"""
    <Primitives.status :if={@candidate["selected"]} tone="success">Selected</Primitives.status>
    <Primitives.status :if={@candidate["refused"]} tone="warning">Refused</Primitives.status>
    <span :if={not @candidate["selected"] and not @candidate["refused"]} class="project-note">
      Not selected
    </span>
    """
  end

  attr :at, DateTime, required: true

  defp day(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@at)}>{Calendar.strftime(@at, "%-d %b %Y")}</time>
    """
  end

  @doc "A verdict's name, as every page and answer gives it."
  @spec verdict_name(atom()) :: String.t()
  def verdict_name(:improved), do: "Improved"
  def verdict_name(:inconclusive), do: "No clear difference"
  def verdict_name(:not_improved), do: "Not improved"
  def verdict_name(:pass_bar_met), do: "Pass bar met"
  def verdict_name(:pass_bar_not_met), do: "Pass bar not met"
  def verdict_name(:completed), do: "Completed"
  def verdict_name(:insufficient_tasks), do: "Too few sound tasks"

  defp verdict_tone(verdict) when verdict in [:improved, :pass_bar_met, :completed], do: "success"
  defp verdict_tone(_verdict), do: "neutral"

  defp verdict_line(:skills, :improved),
    do: "The selected Skill did better than the original on the final test."

  defp verdict_line(:skills, :inconclusive),
    do: "The final test found no clear difference between the selected Skill and the original."

  defp verdict_line(:skills, :not_improved),
    do: "The selected Skill did not do better than the original on the final test."

  defp verdict_line(:evals, :pass_bar_met), do: "The baseline met the agreed pass bar."

  defp verdict_line(:evals, :pass_bar_not_met),
    do: "The baseline fell short of the agreed pass bar."

  defp verdict_line(:environments, :completed),
    do: "The environment passed its task checks and ran a baseline."

  defp verdict_line(:environments, :insufficient_tasks),
    do: "Too few tasks passed their checks to run a baseline."

  defp verdict_line(:models, :improved),
    do: "The trained model met the improvement bar on held-out cases."

  defp verdict_line(:models, :inconclusive),
    do: "The held-out test did not establish a difference."

  defp verdict_line(:models, :not_improved),
    do: "The trained model fell short of the improvement bar."

  defp package_contents(:skills),
    do:
      "One compressed file with the report, your original and selected Skill, the final test’s cases and the steps to run the test again."

  defp package_contents(:evals),
    do: "The report, the reviewed evaluation and how to run it again."

  defp package_contents(:environments),
    do: "The report, any sound tasks and how to check them again."

  defp package_contents(:models), do: "The report, trained adapter, recipe and held-out test."

  # The share of attempts solved, as a percentage of the bar's length.
  defp share(%{"solved" => solved, "attempts" => attempts}), do: solved * 100 / attempts

  defp percent(share), do: round(share * 100)

  # The difference in cases solved, after against before, in words.
  defp difference(0), do: "No change"
  defp difference(difference) when difference > 0, do: "+#{difference} solved"
  defp difference(difference), do: "−#{abs(difference)} solved"

  defp chance(nil), do: "Not measured"
  defp chance(p_value) when p_value < @beyond_chance, do: "Beyond chance"
  defp chance(_p_value), do: "Could be chance"

  defp worse(0), do: "No cases"
  defp worse(1), do: "1 case"
  defp worse(cases), do: "#{cases} cases"

  defp count(1, one, _many), do: "1 #{one}"
  defp count(number, _one, many), do: "#{number} #{many}"

  defp change(before, later) when later < before, do: "worse"
  defp change(before, later) when later > before, do: "better"
  defp change(_before, _later), do: "same"

  defp candidate_name("original"), do: "Original"
  defp candidate_name("rewrite"), do: "Rewrite"
  defp candidate_name("skillopt"), do: "SkillOpt"

  # A setting as a person reads it: `max_turns` 1 is "Max turns: 1", and a
  # count of seconds says so, `time_limit_seconds` 480 being "Time limit: 480 seconds".
  defp setting(name, value) do
    case String.replace_suffix(name, "_seconds", "") do
      ^name -> "#{words(name)}: #{value}"
      base -> "#{words(base)}: #{value} seconds"
    end
  end

  defp words(name), do: name |> String.replace("_", " ") |> String.capitalize()

  defp split(split),
    do:
      "#{count(split["working"], "case", "cases")} to improve the Skill, #{split["selection"]} to choose a candidate, #{split["final"]} for the final test"

  # A size in bytes as a person reads it.
  defp size(bytes) when bytes < 1024, do: "#{bytes} bytes"
  defp size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  # The report is Markdown the factory wrote, stored with the project. It is
  # rendered with raw HTML left out (`RegentBlog.markdown/1`: MDEx with
  # `unsafe: false`, which also drops javascript:, vbscript:, file: and data:
  # addresses), then every link and picture keeps its address only when it is
  # https with a host: any other link is drawn as its words alone, and any other
  # picture without its source.
  defp report_html(markdown) do
    {html, _contents} = RegentBlog.markdown(markdown)

    html
    |> Floki.parse_fragment!()
    |> Floki.traverse_and_update(&https_addresses_only/1)
    |> Floki.raw_html()
  end

  defp https_addresses_only({tag, attributes, children}) do
    attributes =
      Enum.reject(attributes, fn {name, value} ->
        name in ["href", "src"] and not https?(value)
      end)

    {tag, attributes, children}
  end

  defp https_addresses_only(node), do: node

  defp https?(address) do
    case URI.parse(address) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      _other -> false
    end
  end
end
