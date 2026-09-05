defmodule AshPlatformWeb.ShowcaseLive do
  @moduledoc "Loopback-only component workshop. Demo state lives in this LiveView."
  use AshPlatformWeb, :live_view
  alias AshPlatformWeb.Showcase.{Catalog, Sample, Utilities}
  alias Regent.Primitives, as: P

  def mount(_params, _session, socket) do
    face =
      Regent.SceneSpec.face(
        "workshop",
        "Workshop",
        "gate",
        [
          Regent.SceneSpec.add_box("foundation", [0, 0, 0], [8, 2, 8]),
          Regent.SceneSpec.add_box("tower", [2, 2, 2], [4, 6, 4])
        ],
        [
          Regent.SceneSpec.marker("tower",
            label: "Foundation",
            command_id: "tower",
            position: [4, 8, 4],
            sigil: "gate",
            intent: "scene_action"
          )
        ]
      )

    {:ok,
     assign(socket,
       page_title: "Showcase",
       theme: "dark",
       catalog: Catalog.snapshot(),
       product_previews: AshPlatformWeb.Showcase.ProductPreviews.all(),
       form: to_form(%{"title" => "First launch", "quantity" => "1"}, as: :sample),
       errors: [],
       records: [],
       result: nil,
       comments: [],
       identities: [],
       connection_notice: nil,
       scene: Regent.SceneSpec.scene("platform", "regent", "workshop", face),
       scene_status: "Loading scene",
       route_spec: AshPlatformWeb.RouteCatalog.fetch!(:app),
       account: %AshPlatform.AccessContext.AccountControl{
         kind: :preview,
         label: "Fixture",
         profile_path: nil,
         settings_path: nil
       }
     ), layout: false}
  end

  def render(%{live_action: :preview} = assigns) do
    ~H"""
    <AshPlatformWeb.Layouts.app
      flash={%{"info" => "Layout flash · local preview"}}
      inner_content={nil}
    />
    <AshPlatformWeb.Components.Shell.shell
      route_spec={@route_spec}
      account_control={@account}
      content_status={:ready}
      shell_instance={0}
      theme={@theme}
    >
      <:content>
        <div style="padding: 32px">
          <h1>Shell preview</h1><p>Navigation, account control, theme, background.</p><a
            href="/showcase"
            target="_top"
          >Back to showcase</a>
        </div>
      </:content>
    </AshPlatformWeb.Components.Shell.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <div id="showcase" phx-hook="Showcase" class="sc">
      <header class="sc-header">
        <a class="sc-wordmark" href="/showcase">Regent <span>Workshop</span></a>
        <span class="sc-local">Local only</span>
        <a href="/showcase/catalog" class="sc-api">Agent catalog ↗</a>
      </header>
      <div class="sc-layout">
        <aside class="sc-sidebar">
          <nav aria-label="Showcase sections">
            <a href="#foundations">01 <span>Foundations</span></a>
            <a href="#feedback">02 <span>Feedback</span></a>
            <a href="#composition">03 <span>Composition</span></a>
            <a href="#identity">04 <span>Identity & wallets</span></a>
            <a href="#data">05 <span>Ash & utilities</span></a>
            <a href="#inventory">06 <span>Complete inventory</span></a>
          </nav>
          <p class="sc-note">One library.<br />Four identities.</p>
        </aside>
        <main class="sc-main">
          <div class="sc-intro">
            <p class="sc-eyebrow">The working collection</p><h1>
              Shared foundations.<br /><span>Room to explore.</span>
            </h1>
          </div>
          <section
            id="palette-controls"
            class="sc-palette"
            phx-update="ignore"
            aria-label="Palette controls"
          >
            <div class="sc-row sc-between">
              <div class="sc-segment" aria-label="Site palette">
                <button
                  :for={
                    {key, label} <- [
                      {"platform", "Regents"},
                      {"autolaunch", "Autolaunch"},
                      {"patchbay", "Patchbay"},
                      {"techtree", "Techtree"}
                    ]
                  }
                  type="button"
                  data-sc-brand={key}
                  aria-pressed={to_string(key == "platform")}
                >{label}</button>
              </div>
              <div class="sc-segment" aria-label="Color mode">
                <button type="button" data-sc-mode="light" aria-pressed="false">Light</button><button
                  type="button"
                  data-sc-mode="dark"
                  aria-pressed="true"
                >Dark</button>
              </div>
            </div>
            <div class="sc-swatches">
              <label :for={
                {key, name} <- [
                  {"bg", "Background"},
                  {"surface", "Surface"},
                  {"fg", "Text"},
                  {"accent", "Accent"}
                ]
              }>
                <input type="color" data-sc-color={key} aria-label={name <> " color"} value="#202020" /><span>{name}</span><output data-sc-value={
                  key
                }></output>
              </label>
            </div>
            <div class="sc-row sc-between">
              <button type="button" data-sc-reset class="sc-text-button">Reset this palette</button><output
                data-sc-contrast
                class="sc-mono"
                aria-live="polite"
              ></output>
            </div>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="palette-notes"
              summary="Preview scope"
            >
              <p>
                Edits stay in this browser, separately for each site and mode. These are workshop palettes; changing them does not change a deployed site. Keyboard focus and reduced motion remain available. Low-contrast choices are reported above.
              </p>
            </P.disclosure>
          </section>

          <section id="foundations" class="sc-section">
            <.heading number="01" title="Foundations" detail="The small pieces." />
            <div class="sc-grid">
              <article class="sc-card">
                <h3>Buttons</h3><div class="sc-row">
                  <P.button phx-click="example_action">Primary</P.button><P.button
                    variant="secondary"
                    phx-click="example_action"
                  >Secondary</P.button><P.button variant="quiet" phx-click="example_action">Quiet</P.button><P.button disabled>Disabled</P.button>
                </div><p :if={@result && @result[:example]} role="status">{@result.example}</p><.api
                  module="Regent.Primitives"
                  function="button"
                />
              </article>
              <article class="sc-card">
                <h3>Typography</h3><p class="sc-type-display">Aa / 0123</p><p>
                  Geist · functional, clear, familiar.
                </p><code>0x71C7…976F</code><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="type-tokens"
                  summary="Type & spacing tokens"
                >
                  <p>
                    Display: Geist Pixel. Interface: Geist Sans. Data: Geist Mono. Space: 4 / 8 / 12 / 16 / 24 / 32 / 48 px.
                  </p>
                </P.disclosure>
              </article>
              <article class="sc-card">
                <h3>Fields</h3><P.field :let={field} id="preview-email" label="Email">
                  <input
                    id={field.id}
                    type="email"
                    placeholder="you@example.com"
                    aria-describedby={field.described_by}
                  /><:hint>Optional contact address.</:hint>
                </P.field><P.field :let={field} id="preview-network" label="Network">
                  <select id={field.id}><option>Base</option><option>Ethereum</option></select>
                </P.field><P.field
                  :let={field}
                  id="preview-invalid"
                  label="Required name"
                  errors={["Enter a name."]}
                >
                  <input
                    id={field.id}
                    aria-invalid={field.aria_invalid}
                    aria-describedby={field.described_by}
                  />
                </P.field><.api module="Regent.Primitives" function="field" />
              </article>
              <article class="sc-card">
                <h3>Disclosure</h3><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="disclosure-example"
                  summary="What is shared?"
                >
                  <p>
                    Components own presentation. Each application supplies actions, routes, authorization and state.
                  </p><code>Regent.Primitives.disclosure/1</code>
                </P.disclosure><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="disclosure-open"
                  summary="Open by default"
                  open
                >
                  <p>
                    Detail stays in the DOM when collapsed, and the catalog exposes the inventory independently of visual state.
                  </p>
                </P.disclosure><.api module="Regent.Primitives" function="disclosure" />
              </article>
            </div>
          </section>

          <section id="feedback" class="sc-section">
            <.heading number="02" title="Feedback" detail="A state worth showing." /><div class="sc-grid">
              <article class="sc-card">
                <h3>Status</h3><div class="sc-row">
                  <P.status :for={tone <- ~w(neutral info success warning error)} tone={tone}>
                    {String.capitalize(tone)}
                  </P.status>
                </div><.api module="Regent.Primitives" function="status" /><h3>Notices</h3><P.notice
                  :for={
                    {tone, text} <- [
                      {"info", "Ready for the next step."},
                      {"success", "Saved successfully."},
                      {"warning", "Review the current network."},
                      {"error", "The wallet rejected this request."}
                    ]
                  }
                  tone={tone}
                >
                  {text}
                </P.notice><.api module="Regent.Primitives" function="notice" />
              </article>
              <article class="sc-card">
                <h3>Empty states</h3><P.empty_state title="Nothing here yet.">
                  Your first item will appear here.<:action>
                    <P.button phx-click="example_action" variant="secondary">Create item</P.button>
                  </:action>
                </P.empty_state><.api module="Regent.Primitives" function="empty_state" />
              </article>
            </div>
          </section>

          <section id="composition" class="sc-section">
            <.heading number="03" title="Composition" detail="Pieces working together." />
            <div class="sc-grid">
              <Regent.Panels.chamber
                id="showcase-chamber"
                title="Current step"
                subtitle="Chamber"
                summary="Slot-based content"
              >
                <P.status tone="success">Ready</P.status><:actions>
                  <P.button variant="quiet" phx-click="example_action">Edit</P.button>
                </:actions><:footer>Application-owned footer</:footer>
              </Regent.Panels.chamber><Regent.Panels.ledger
                id="showcase-ledger"
                title="Activity"
                subtitle="Ledger"
              >
                <dl class="sc-facts">
                  <dt>Network</dt><dd>Base</dd><dt>State</dt><dd>Confirmed</dd>
                </dl><:actions>
                  <P.button variant="quiet" phx-click="example_action">Copy</P.button>
                </:actions><:footer>Application-owned records</:footer>
              </Regent.Panels.ledger>
            </div>
            <article class="sc-card">
              <h3>Spatial surface <small>{@scene_status}</small></h3><Regent.Components.surface
                id="showcase-surface"
                scene={@scene}
                sigil_pack_url="/showcase/sigils.svg"
              >
                <:header_strip>Shared scene · select a marker</:header_strip><:chamber>
                  <span>Chamber slot</span>
                </:chamber><:ledger><span>Ledger slot</span></:ledger>
              </Regent.Components.surface><.api module="Regent.Components" function="surface" />
            </article>
            <article class="sc-card">
              <h3>Sigils</h3><div class="sc-row">
                <span :for={name <- ~w(gate eye seed fuse seal wedge)} class="sc-sigil"><Regent.Panels.icon
                  name={name}
                  title={name}
                  sprite_path="/showcase/sigils.svg"
                />{name}</span>
              </div><.api module="Regent.Panels" function="icon" />
            </article>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="backgrounds-detail"
              summary="Backgrounds · all five product slots + shared grid"
            >
              <div class="sc-backgrounds">
                <figure :for={slot <- [:home, :regents_labs, :formation, :regent_record, :autolaunch]}>
                  <AshPlatformWeb.Components.Background.background slot={slot} /><figcaption>
                    {slot}
                  </figcaption>
                </figure><figure>
                  <Regent.BackgroundGrid.background_grid id="showcase-grid" /><figcaption>
                    Shared grid
                  </figcaption>
                </figure>
              </div>
            </P.disclosure>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="shell-detail"
              summary="Shell, theme toggle & layouts"
            >
              <iframe
                id="shell-preview"
                title="Live shell component preview"
                src="/showcase/preview"
                loading="lazy"
              ></iframe><p>
                The root layout renders this document. The preview renders the app layout, navigation, account control and theme toggle.
              </p>
            </P.disclosure>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="comments-detail"
              summary="Comment ledger · local fixture"
            >
              <AshPlatformWeb.Components.CommentLedger.comment_ledger
                comments={@comments}
                status={:ready}
                current_human_id={1}
                request_id="showcase"
              />
            </P.disclosure>
          </section>

          <section id="identity" class="sc-section">
            <.heading number="04" title="Identity & wallets" detail="See each request through." />
            <div class="sc-grid">
              <article class="sc-card">
                <h3>Wallet lifecycle <small>Fixture</small></h3><div
                  id="wallet-fixture"
                  phx-hook="ShowcaseWallet"
                  phx-update="ignore"
                >
                  <div class="sc-row">
                    <P.button data-demo-connect>Connect fixture</P.button><P.button
                      variant="quiet"
                      data-demo-disconnect
                    >Disconnect</P.button>
                  </div><p data-demo-wallet role="status">Disconnected</p><label for="fixture-outcome">Next outcome</label><select
                    id="fixture-outcome"
                    data-demo-outcome
                  ><option value="confirmed">Confirmed</option><option value="rejected">
                    Rejected
                  </option><option value="reverted">Reverted</option></select><P.button data-demo-send>Send fixture transaction</P.button><ol
                    data-demo-results
                    aria-live="polite"
                  >
                  </ol>
                </div><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="wallet-contract"
                  summary="Execution contract"
                >
                  <p>
                    This isolated provider never accesses a real wallet or network. Each press creates its own request, including while another is pending. Disconnect affects only this fixture. The demo uses the existing wallet selection utility.
                  </p>
                </P.disclosure>
              </article>
              <article class="sc-card">
                <h3>Privy <small>Existing app controls</small></h3><div class="sc-row">
                  <P.button data-account-target="sign-in">Connect Privy</P.button><P.button
                    variant="secondary"
                    data-account-target="sign-out"
                  >Disconnect Privy</P.button>
                </div><p id="account-auth-status" role="status" phx-update="ignore" hidden></p><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="privy-scope"
                  summary="Uses your configured identity"
                >
                  <p>
                    These buttons use the application's existing Privy bridge and session endpoints. Connecting may open Privy; disconnecting ends the local app session. Requires a configured Privy app and an allowed local origin. Wallet fixture state is separate.
                  </p>
                </P.disclosure><h3>Product actions</h3><div class="sc-row">
                  <a href="/stake">Stake ↗</a><a href="/redeem">Redeem ↗</a><a href="/autolaunch/create">Launch ↗</a>
                </div><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="real-actions"
                  summary="Real action requirements"
                >
                  <p>
                    These destinations use their existing authentication and wallet verification. Transactions require a wallet signature. The showcase does not submit them.
                  </p>
                </P.disclosure>
              </article>
            </div>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="connections-detail"
              summary="Verified connections · local fixture"
            >
              <AshPlatformWeb.Components.VerifiedConnections.verified_connections
                id="showcase-connections"
                identities={@identities}
                authenticated
                notice={@connection_notice}
                description="Local presentation fixture"
              />
            </P.disclosure>
            <P.disclosure
              :for={{preview, index} <- Enum.with_index(@product_previews)}
              phx-mounted={JS.ignore_attributes("open")}
              id={"product-preview-#{index}"}
              summary={preview.name <> " · signed-out preview"}
            >
              <iframe title={preview.name} srcdoc={preview.document} sandbox="" loading="lazy"></iframe><p>
                Static, inert product composition. No hooks, sign-in or transaction handlers run inside this preview.
              </p>
            </P.disclosure>
          </section>

          <section id="data" class="sc-section">
            <.heading number="05" title="Ash & utilities" detail="Real functions. Bounded inputs." />
            <div class="sc-grid">
              <article class="sc-card">
                <h3>Ash action <small>In memory</small></h3><.form
                  for={@form}
                  id="sample-form"
                  phx-submit="create_sample"
                >
                  <P.field :let={field} id="sample-title" label="Title" errors={@errors}>
                    <input
                      id={field.id}
                      name="sample[title]"
                      value={@form[:title].value}
                      aria-invalid={field.aria_invalid}
                      aria-describedby={field.described_by}
                    />
                  </P.field><P.field :let={field} id="sample-quantity" label="Quantity">
                    <input
                      id={field.id}
                      name="sample[quantity]"
                      type="number"
                      value={@form[:quantity].value}
                    />
                  </P.field><P.button type="submit">Run create action</P.button>
                </.form><ul id="sample-records">
                  <li :for={record <- @records}>{record.title} × {record.quantity}</li>
                </ul><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="ash-demo-notes"
                  summary="Resource & validation"
                >
                  <p>
                    Runs Ash.Changeset.for_create and Ash.create against Ash.DataLayer.Simple. Title: 2–80 characters. Quantity: 1–100. Records live only in this view; no database writes. AshPhoenix is not installed in this application; this form uses Phoenix with an Ash action.
                  </p>
                </P.disclosure>
              </article>
              <article class="sc-card">
                <h3>Address, tokens & contracts</h3><form id="utility-form" phx-submit="run_utility">
                  <label for="utility-kind">Function</label><select id="utility-kind" name="kind"><option value="address">
                    Address checksum
                  </option><option value="amount">Token units</option><option value="calldata">
                    ERC20 approve calldata
                  </option><option value="privy_valid">Privy: valid fixture token</option><option value="privy_expired">
                    Privy: expired fixture token
                  </option><option value="privy_audience">Privy: wrong audience</option></select><label for="utility-address">Address / spender</label><input
                    id="utility-address"
                    name="address"
                    value="0x1111111111111111111111111111111111111111"
                  /><label for="utility-amount">Integer amount</label><input
                    id="utility-amount"
                    name="amount"
                    value="1000000000000000000"
                  /><label for="utility-decimals">Token decimals</label><input
                    id="utility-decimals"
                    name="decimals"
                    value="18"
                  /><P.button type="submit">Run locally</P.button>
                </form><pre id="utility-result" role="status">{if @result && !@result[:example], do: Jason.encode!(@result, pretty: true)}</pre><button
                  type="button"
                  data-sc-copy="utility-result"
                  class="sc-text-button"
                >Copy result</button><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="utility-notes"
                  summary="Ownership & effects"
                >
                  <p>
                    Address, ABI and token formatting currently belong to Regents. Calldata is encoded locally and never submitted. Privy verification uses an ephemeral fixture key and the real RegentPrivy verifier, with valid, expired and wrong-audience examples. Fixture tokens never enter the session endpoint. Shared APIs are labeled in the inventory below.
                  </p>
                </P.disclosure>
              </article>
              <article class="sc-card">
                <h3>Postgres <small>Read only</small></h3><P.button
                  variant="secondary"
                  phx-click="database"
                >Check isolated database</P.button><P.disclosure
                  phx-mounted={JS.ignore_attributes("open")}
                  id="database-notes"
                  summary="Diagnostic boundary"
                >
                  <p>
                    Runs SELECT current_database(), 1 only against this worktree's prepared loopback test database. Other database configurations are refused. No arbitrary query, fixture writes, schema changes or resets.
                  </p>
                </P.disclosure>
              </article>
            </div>
          </section>

          <section id="inventory" class="sc-section">
            <.heading
              number="06"
              title="Complete inventory"
              detail="Inspect without expanding the page."
            />
            <p class="sc-note">
              {length(@catalog.components)} component entries · {length(@catalog.aliases)} aliases · {length(
                @catalog.domains
              )} Ash domains
            </p>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="component-inventory"
              summary="Every installed design component"
            >
              <div :for={item <- @catalog.components} class="sc-inventory-row">
                <code>{item.module}.{item.function}/1</code><small>Attributes: {Enum.join(
                  item.attributes,
                  ", "
                )} · Slots: {Enum.join(item.slots, ", ")}</small>
              </div><div :for={item <- @catalog.aliases} class="sc-inventory-row">
                <code>{item.name}</code><small>Alias of {item.target}</small>
              </div>
            </P.disclosure>
            <P.disclosure
              :for={{domain, index} <- Enum.with_index(@catalog.domains)}
              phx-mounted={JS.ignore_attributes("open")}
              id={"domain-#{index}"}
              summary={domain.name}
            >
              <div :for={resource <- domain.resources} class="sc-inventory-row">
                <code>{resource.name}</code><p>
                  Actions: {Enum.map_join(resource.actions, ", ", &"#{&1.name} (#{&1.type})")}
                </p><small>Attributes: {Enum.map_join(
                  resource.attributes,
                  ", ",
                  &"#{&1.name}#{if &1.public, do: "", else: " [private]"}"
                )}</small>
              </div>
            </P.disclosure>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="utility-inventory"
              summary={"Utility API · #{length(@catalog.utilities)} modules"}
            >
              <div :for={item <- @catalog.utilities} class="sc-inventory-row">
                <code>{item.name}</code><small>{item.owner}</small><p>
                  {Enum.join(item.functions, " · ")}
                </p>
              </div>
            </P.disclosure>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="coverage-scope"
              summary="Coverage boundary"
            >
              <p>
                The visual inventory covers every canonical component in regent_ui and this application's components directory, with aliases identified. Product pages compose these pieces and retain their own behavior. Ash resources are inspected through installed metadata; this route never enumerates their records. Utilities list installed shared libraries and the Regents wallet, staking, redemption and database modules. This is not a claim that product-specific utilities are already shared across four apps.
              </p>
            </P.disclosure>
          </section>
          <footer class="sc-footer">
            <span>Regent / Component workshop</span><a href="#showcase">Back to top ↑</a>
          </footer>
        </main>
      </div>
    </div>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :detail, :string, required: true

  defp heading(assigns) do
    ~H"""
    <div class="sc-heading">
      <span>{@number}</span><h2>{@title}</h2><p>{@detail}</p>
    </div>
    """
  end

  attr :module, :string, required: true
  attr :function, :string, required: true

  defp api(assigns) do
    ~H"""
    <details class="sc-api-note">
      <summary>API <span aria-hidden="true">›</span></summary><code>{@module}.{@function}/1</code>
    </details>
    """
  end

  def handle_event("create_sample", %{"sample" => params}, socket) do
    changeset = Ash.Changeset.for_create(Sample, :create, params)

    case Ash.create(changeset, authorize?: false) do
      {:ok, record} ->
        {:noreply,
         assign(socket,
           records: [record | socket.assigns.records],
           errors: [],
           form: to_form(params, as: :sample)
         )}

      {:error, error} ->
        {:noreply,
         assign(socket, errors: [Exception.message(error)], form: to_form(params, as: :sample))}
    end
  end

  def handle_event("run_utility", params, socket) do
    result =
      case params["kind"] do
        "privy_valid" -> Utilities.privy(:valid)
        "privy_expired" -> Utilities.privy(:expired)
        "privy_audience" -> Utilities.privy(:audience)
        "address" -> Utilities.address(params["address"] || "")
        "amount" -> Utilities.amount(params["amount"] || "", params["decimals"] || "")
        "calldata" -> Utilities.calldata(params["address"] || "", params["amount"] || "")
        _ -> %{error: "Choose a listed utility."}
      end

    {:noreply, assign(socket, :result, result)}
  end

  def handle_event("database", _, socket),
    do: {:noreply, assign(socket, :result, Utilities.database())}

  def handle_event("example_action", _, socket),
    do: {:noreply, assign(socket, :result, %{example: "Action received."})}

  def handle_event("post_comment", %{"comment" => %{"body" => body}}, socket) do
    if String.trim(body) != "" and String.length(body) <= 2_000 do
      comment = %{
        id: System.unique_integer([:positive]),
        author_id: 1,
        author: %{display_name: "Workshop visitor"},
        body: body,
        inserted_at: DateTime.utc_now()
      }

      {:noreply, assign(socket, :comments, [comment | socket.assigns.comments])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, :comments, Enum.reject(socket.assigns.comments, &(to_string(&1.id) == id)))}

  def handle_event(
        "request_verified_connection",
        %{"provider" => provider, "action" => action},
        socket
      ) do
    provider = Map.get(%{"x" => :x, "github" => :github, "farcaster" => :farcaster}, provider)
    identities = Enum.reject(socket.assigns.identities, &(&1.provider == provider))

    identities =
      if action == "link" and not is_nil(provider),
        do: [
          %{provider: provider, username: "workshop", display_name: "Workshop fixture"}
          | identities
        ],
        else: identities

    {:noreply,
     assign(socket,
       identities: identities,
       connection_notice: %{tone: :info, message: "Fixture updated. No provider request."}
     )}
  end

  def handle_event("regent:surface_ready", _, socket),
    do: {:noreply, assign(socket, :scene_status, "Ready")}

  def handle_event("regent:surface_error", _, socket),
    do: {:noreply, assign(socket, :scene_status, "Scene unavailable")}

  def handle_event("regent:node_select", %{"target_id" => id}, socket),
    do: {:noreply, assign(socket, :scene_status, "Selected #{id}")}

  def handle_event("regent:node_hover", _, socket), do: {:noreply, socket}
end
