defmodule AshPlatformWeb.ShowcaseLive do
  @moduledoc "Loopback-only component workshop. Demo state lives in this LiveView."
  use AshPlatformWeb, :live_view
  alias AshPlatformWeb.Showcase.{Catalog, Sample, Utilities}
  alias Regent.Primitives, as: P
  alias Regent.Structure, as: S

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Showcase",
       privy_mode: privy_mode(),
       theme: "dark",
       catalog: Catalog.snapshot(),
       capabilities: capability_samples(),
       ratio_bps: 5620,
       ratio_state: "sample",
       product_previews: AshPlatformWeb.Showcase.ProductPreviews.all(),
       form: to_form(%{"title" => "First launch", "quantity" => "1"}, as: :sample),
       errors: [],
       records: [],
       empty_items: [],
       empty_error: nil,
       chamber_title: "Current step",
       chamber_editing: false,
       chamber_form: to_form(%{"title" => "Current step"}, as: :chamber),
       chamber_errors: [],
       result: nil,
       comments: [],
       comment_notice: nil,
       comment_draft: "",
       identities: [],
       connection_notice: nil,
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
    <S.frame id="showcase" phx-hook="Showcase" class="sc">
      <header class="sc-header">
        <a class="sc-wordmark" href="/showcase">Regent <span>Workshop</span></a>
        <span class="sc-local">Local only</span>
        <a href="/showcase/catalog" class="sc-api">Agent catalog ↗</a>
        <a href="/showcase/privy" class="sc-api">Privy reference ↗</a>
      </header>
      <div class="sc-layout">
        <aside class="sc-sidebar">
          <nav aria-label="Showcase sections">
            <a href="#foundations">01 <span>Foundations</span></a>
            <a href="#capabilities">02 <span>Capabilities</span></a>
            <a href="#feedback">03 <span>Feedback</span></a>
            <a href="#composition">04 <span>Composition</span></a>
            <a href="#staking-summary">05 <span>Staking overview</span></a>
            <a href="#identity">06 <span>Identity & wallets</span></a>
            <a href="#data">07 <span>Ash & utilities</span></a>
            <a href="#inventory">08 <span>Complete inventory</span></a>
          </nav>
          <p class="sc-note">One library.<br />Four identities.</p>
        </aside>
        <main class="sc-main">
          <S.row rail={false} class="sc-intro">
            <p class="sc-eyebrow rg-support-band">The working collection</p><h1>
              Shared foundations.<br /><span>Room to explore.</span>
            </h1>
          </S.row>
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
            <div class="sc-theme-options" role="group" aria-label="Site themes">
              <button
                :for={
                  {key, label, mode} <-
                    for {key, label} <- [
                          {"platform", "Regents"},
                          {"autolaunch", "Autolaunch"},
                          {"patchbay", "Patchbay"},
                          {"techtree", "Techtree"}
                        ],
                        mode <- ["light", "dark"],
                        do: {key, label, mode}
                }
                type="button"
                data-sc-theme={key <> ":" <> mode}
                aria-pressed={to_string(key == "platform" and mode == "dark")}
              >
                <span class="sc-theme-sample" aria-hidden="true"><span>Aa</span><i></i></span>
                <span>{label} <small>{mode}</small></span>
              </button>
            </div>
            <div class="sc-swatches">
              <label :for={
                {key, name} <- [
                  {"bg", "Background"},
                  {"surface", "Surface"},
                  {"fg", "Text"},
                  {"accent", "Primary"}
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
            <div class="sc-row sc-shimmer-control">
              <label for="shimmer-color">Shimmer color</label>
              <input id="shimmer-color" type="color" data-sc-shimmer-color value="#FF5B19" />
              <output data-sc-shimmer-value>Automatic</output>
              <button type="button" data-sc-shimmer-reset class="sc-text-button">Use automatic color</button>
            </div>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="palette-notes"
              summary="Palette & structural details"
            >
              <p>
                Source: the shared design-system package. Regents uses charcoal, Autolaunch tangerine, Patchbay platinum, and Techtree powder blue. Preview edits stay in this browser; shared source changes reach each site through its asset build.
              </p>
              <dl class="sc-token-list" data-sc-tokens></dl>
            </P.disclosure>
          </section>

          <section id="foundations" class="sc-section">
            <.heading number="01" title="Foundations" detail="The small pieces." />
            <div class="sc-grid">
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
                  <h3>Buttons</h3><div class="sc-row">
                    <P.button phx-click="example_action">Primary</P.button><P.button
                      variant="secondary"
                      phx-click="example_action"
                    >Secondary</P.button><P.button variant="quiet" phx-click="example_action">Quiet</P.button><P.button disabled>Disabled</P.button>
                  </div><p :if={@result && @result[:example]} role="status">{@result.example}</p><.api
                    module="Regent.Primitives"
                    function="button"
                  />
                </S.panel>
              </div>
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
                  <h3>Typography</h3><S.technical_figure class="rg-support-figure">
                    <p class="sc-type-display">Aa / 0123</p><:caption>
                      Pixel Square / regular 400
                    </:caption>
                  </S.technical_figure><p>
                    Geist Sans · body copy and interface.
                  </p><code>0x71C7…976F</code><P.disclosure
                    phx-mounted={JS.ignore_attributes("open")}
                    id="type-tokens"
                    summary="Type & spacing tokens"
                  >
                    <p>
                      Titles & subtitles: Geist Pixel Square, weight 400. Body & interface: Geist Sans. Code & technical identifiers: Geist Mono. Space: 8 / 16 / 24 / 32 / 40 / 48 / 64 px.
                    </p>
                  </P.disclosure>
                </S.panel>
              </div>
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
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
                </S.panel>
              </div>
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
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
                </S.panel>
              </div>
            </div>
          </section>

          <section id="capabilities" class="sc-section">
            <.heading number="02" title="Capabilities" detail="One component. Your images and copy." />
            <div class="rg-feature-grid">
              <S.capability_card
                :for={card <- @capabilities}
                id={"capability-#{card.index}"}
                title={card.title}
                description={card.description}
                index={card.index}
                tone={card.tone}
                image_src={card.image}
                image_alt="Regents crown"
              >
                <:media>
                  <svg
                    :if={!card.image}
                    viewBox="0 0 240 240"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.2"
                    aria-hidden="true"
                  >
                    <path d="M12 24V12H24 M216 12H228V24 M228 216V228H216 M24 228H12V216" />
                    <circle
                      :for={r <- [80, 62, 44, 26]}
                      :if={card.kind == :circles}
                      cx="120"
                      cy={190 - r}
                      r={r}
                    />
                    <path
                      :for={y <- [36, 60, 84, 108, 132, 156]}
                      :if={card.kind == :triangle}
                      d={"M120 #{y}L40 194H200Z M120 #{y}V194"}
                    />
                  </svg>
                </:media>
                <:actions>
                  <a href={card.href} class="rg-button rg-button--quiet">{card.action} ↗</a>
                </:actions>
              </S.capability_card>
            </div>
            <p class="sc-note">
              Hover or focus a card for the slower sweep. The color control above applies to cards and primary buttons.
            </p>
            <.api module="Regent.Structure" function="capability_card" />
          </section>

          <section id="feedback" class="sc-section">
            <.heading number="03" title="Feedback" detail="A state worth showing." /><div class="sc-grid">
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
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
                </S.panel>
              </div>
              <div class="sc-example rg-feature">
                <S.panel id="empty-state-demo" class="sc-card">
                  <h3>Empty states</h3>
                  <div aria-live="polite">
                    <P.empty_state :if={@empty_items == []} title="Nothing here yet.">
                      Your first item will appear here.
                    </P.empty_state>
                    <ul :if={@empty_items != []} id="empty-state-items">
                      <li :for={item <- @empty_items}>{item.title}</li>
                    </ul>
                    <P.notice :if={@empty_error} tone="error">{@empty_error}</P.notice>
                  </div>
                  <div class="sc-row">
                    <P.button id="add-item" phx-click="create_item" variant="secondary">
                      {if @empty_items == [], do: "Create item", else: "Add item"}
                    </P.button>
                    <P.button :if={@empty_items != []} phx-click="reset_items" variant="quiet">
                      Reset items
                    </P.button>
                  </div>
                  <p>Local Ash records only; reload clears this example.</p>
                  <.api module="Regent.Primitives" function="empty_state" />
                </S.panel>
              </div>
            </div>
          </section>

          <section id="composition" class="sc-section">
            <.heading number="04" title="Composition" detail="Pieces working together." />
            <div class="sc-grid">
              <Regent.Panels.chamber
                id="showcase-chamber"
                class="rg-panel--accent"
                title={@chamber_title}
                subtitle="Chamber"
                summary="Slot-based content"
              >
                <.form
                  :if={@chamber_editing}
                  for={@chamber_form}
                  id="chamber-form"
                  phx-submit="save_chamber"
                >
                  <P.field :let={field} id="chamber-title" label="Step title" errors={@chamber_errors}>
                    <input
                      id={field.id}
                      name="chamber[title]"
                      value={@chamber_form[:title].value}
                      aria-invalid={field.aria_invalid}
                      aria-describedby={field.described_by}
                      phx-mounted={JS.focus()}
                      required
                      maxlength="80"
                    />
                  </P.field>
                  <div class="sc-row">
                    <P.button type="submit">Save title</P.button>
                    <P.button variant="quiet" phx-click="cancel_chamber">Cancel</P.button>
                  </div>
                </.form>
                <P.status :if={!@chamber_editing} tone="success">Ready</P.status><:actions>
                  <P.button :if={!@chamber_editing} variant="quiet" phx-click="edit_chamber">Edit</P.button>
                </:actions><:footer>Edits stay in this local workshop.</:footer>
              </Regent.Panels.chamber><Regent.Panels.ledger
                id="showcase-ledger"
                title="Activity"
                subtitle="Ledger"
              >
                <dl id="showcase-ledger-content" class="sc-facts">
                  <dt>Network</dt><dd>Base</dd><dt>State</dt><dd>Confirmed</dd>
                </dl><:actions>
                  <P.button variant="quiet" data-sc-copy="showcase-ledger-content">Copy</P.button>
                </:actions><:footer>Application-owned records</:footer>
              </Regent.Panels.ledger>
            </div>
            <P.disclosure
              phx-mounted={JS.ignore_attributes("open")}
              id="backgrounds-detail"
              summary="Background compatibility components · retired"
            >
              <div class="sc-backgrounds">
                <figure :for={slot <- [:home]}>
                  <AshPlatformWeb.Components.Background.background slot={slot} /><figcaption>
                    {slot}
                  </figcaption>
                </figure><figure>
                  <Regent.SiteBackground.site_background /><figcaption>
                    Retired shared background (intentionally empty)
                  </figcaption>
                </figure>
              </div>
              <p>
                Page SVG backgrounds are disabled in the shared structural theme. These compatibility components remain mounted for inventory coverage; the workshop does not install a page background.
              </p>
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
                notice={@comment_notice}
                draft={@comment_draft}
                current_human_id={1}
                request_id="showcase"
              />
            </P.disclosure>
          </section>

          <section id="staking-summary" class="sc-section">
            <.heading
              number="05"
              title="Staking overview"
              detail="Bracketed metrics / orange signal."
            />
            <p class="sc-note">
              Presentation preview for the Regents staking page. These are example supply
              percentages and an illustrative 30-day change, not live contract data or yield.
            </p>
            <form id="ratio-preview" phx-change="set_ratio_preview" class="sc-ratio-preview">
              <P.field :let={field} id="ratio-state" label="Preview state">
                <select id={field.id} name="ratio[state]">
                  <option
                    :for={
                      {value, label} <- [
                        {"sample", "Example · 56.2% staked"},
                        {"zero", "Zero staked"},
                        {"full", "Fully staked"},
                        {"unavailable", "Data unavailable"}
                      ]
                    }
                    value={value}
                    selected={value == @ratio_state}
                  >
                    {label}
                  </option>
                </select>
              </P.field>
            </form>
            <S.ratio_card
              id="staking-ratio"
              eyebrow="Regent"
              title="Staking"
              value_bps={@ratio_bps}
              label="Staked supply"
              remainder_label="Unstaked supply"
              change={if @ratio_state == "sample", do: "+3.2 pp · 30d demo"}
              footer_label="Staking context"
            >
              <:footer>
                <ul class="sc-ratio-context" aria-label="Preview staking context">
                  <li :for={label <- ["Base", "REGENT", "USDC", "ERC-20"]}>{label}</li>
                </ul>
              </:footer>
              <:footer_badge>Preview only</:footer_badge>
            </S.ratio_card>
            <.api module="Regent.Structure" function="ratio_card" />
          </section>

          <section id="identity" class="sc-section">
            <.heading number="06" title="Identity & wallets" detail="See each request through." />
            <div class="sc-grid">
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
                  <h3>Wallet lifecycle <small>Fixture</small></h3><div
                    id="wallet-fixture"
                    class="rg-field"
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
                </S.panel>
              </div>
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
                  <h3>Privy <small>Real app session</small></h3>
                  <div data-sc-privy-mode={@privy_mode}>
                    <div id="account-control" class="sc-row">
                      <P.button
                        :if={@privy_mode == :configured && @account_control.kind == :sign_in}
                        data-account-target="sign-in"
                      >Connect Privy</P.button>
                      <P.button
                        :if={@privy_mode == :configured && @account_control.kind == :signed_in}
                        variant="secondary"
                        data-account-target="sign-out"
                      >Disconnect Privy</P.button>
                      <P.button
                        :if={@privy_mode != :configured}
                        disabled
                        aria-describedby="privy-unavailable"
                      >Connect Privy</P.button>
                    </div>
                    <p :if={@privy_mode == :configured && @account_control.kind == :signed_in}>
                      Signed in as {@account_control.label}.
                    </p>
                    <p :if={@privy_mode == :fixture} id="privy-unavailable">
                      Real sign-in is unavailable on this test-fixture server. Use a development
                      server with your real Privy app, verifier and an allowed local origin.
                      The separate wallet demo does not authenticate an account.
                    </p>
                    <p :if={@privy_mode == :unconfigured} id="privy-unavailable">
                      Real sign-in is unavailable until this server has a Privy app ID and
                      verification key. The Privy app must also allow this local origin.
                    </p>
                  </div><p id="account-auth-status" role="status" phx-update="ignore" hidden></p><P.disclosure
                    phx-mounted={JS.ignore_attributes("open")}
                    id="privy-scope"
                    summary="Uses your configured identity"
                  >
                    <p>
                      These controls use the application's existing Privy bridge and verified
                      session loader. Only the action matching the server's current account
                      state is offered. Connecting may open Privy; disconnecting ends the local
                      app session. Provider readiness and the allowed origin still need to be
                      verified with a real account. Wallet fixture state is separate.
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
                </S.panel>
              </div>
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
            <.heading number="07" title="Ash & utilities" detail="Real functions. Bounded inputs." />
            <div class="sc-grid">
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
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
                </S.panel>
              </div>
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
                  <h3>Address, tokens & contracts</h3><form
                    id="utility-form"
                    class="rg-field"
                    phx-submit="run_utility"
                  >
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
                </S.panel>
              </div>
              <div class="sc-example rg-feature">
                <S.panel class="sc-card">
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
                </S.panel>
              </div>
            </div>
          </section>

          <section id="inventory" class="sc-section">
            <.heading
              number="08"
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
              summary="Active design components"
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
                The visual inventory covers the active components from regent_ui and this application's components directory, with aliases identified. Product pages compose these pieces and retain their own behavior. Ash resources are inspected through installed metadata; this route never enumerates their records. Utilities list installed shared libraries and the Regents wallet, staking, redemption and database modules. This is not a claim that product-specific utilities are already shared across four apps.
              </p>
            </P.disclosure>
          </section>
          <footer class="sc-footer">
            <span>Regent / Component workshop</span><a href="#showcase">Back to top ↑</a>
          </footer>
        </main>
      </div>
    </S.frame>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :detail, :string, required: true

  defp heading(assigns) do
    ~H"""
    <S.section_bar class="sc-heading">
      <span>{@number}</span><h2 class="rg-section-bar__label">{@title}</h2><p>{@detail}</p>
    </S.section_bar>
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

  def handle_event("set_ratio_preview", %{"ratio" => %{"state" => state}}, socket) do
    case Map.fetch(
           %{"sample" => 5620, "zero" => 0, "full" => 10_000, "unavailable" => nil},
           state
         ) do
      {:ok, value} -> {:noreply, assign(socket, ratio_state: state, ratio_bps: value)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("create_sample", %{"sample" => params}, socket) do
    changeset = Ash.Changeset.for_create(Sample, :create, params)

    case Ash.create(changeset) do
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

  def handle_event("create_item", _, socket) do
    params = %{title: "Workshop item #{length(socket.assigns.empty_items) + 1}", quantity: 1}

    case Sample |> Ash.Changeset.for_create(:create, params) |> Ash.create() do
      {:ok, item} ->
        {:noreply,
         assign(socket, empty_items: socket.assigns.empty_items ++ [item], empty_error: nil)}

      {:error, error} ->
        {:noreply, assign(socket, :empty_error, Exception.message(error))}
    end
  end

  def handle_event("reset_items", _, socket),
    do: {:noreply, assign(socket, empty_items: [], empty_error: nil)}

  def handle_event("edit_chamber", _, socket),
    do:
      {:noreply,
       assign(socket,
         chamber_editing: true,
         chamber_errors: [],
         chamber_form: to_form(%{"title" => socket.assigns.chamber_title}, as: :chamber)
       )}

  def handle_event("cancel_chamber", _, socket),
    do: {:noreply, assign(socket, chamber_editing: false, chamber_errors: [])}

  def handle_event("save_chamber", %{"chamber" => params}, socket) do
    # Reuse the local sample action's title validation, never a product resource.
    case Sample
         |> Ash.Changeset.for_create(:create, Map.take(params, ["title"]))
         |> Ash.create() do
      {:ok, item} ->
        {:noreply,
         assign(socket, chamber_title: item.title, chamber_editing: false, chamber_errors: [])}

      {:error, error} ->
        {:noreply,
         assign(socket,
           chamber_errors: [Exception.message(error)],
           chamber_form: to_form(params, as: :chamber)
         )}
    end
  end

  def handle_event("run_utility", params, socket),
    do: {:noreply, assign(socket, :result, run_utility(params["kind"], params))}

  def handle_event("database", _, socket),
    do: {:noreply, assign(socket, :result, Utilities.database())}

  def handle_event("example_action", _, socket),
    do: {:noreply, assign(socket, :result, %{example: "Action received."})}

  def handle_event("post_comment", %{"comment" => %{"body" => body}}, socket) do
    case AshPlatform.Discussions.Markdown.normalize_and_validate(body) do
      {:ok, body} ->
        comment = %{
          id: System.unique_integer([:positive]),
          author_id: 1,
          author: %{display_name: "Workshop visitor"},
          body: body,
          inserted_at: DateTime.utc_now()
        }

        {:noreply,
         assign(socket,
           comments: [comment | socket.assigns.comments],
           comment_draft: "",
           comment_notice: %{tone: :success, message: "Comment posted locally."}
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           comment_draft: body,
           comment_notice: %{
             tone: :error,
             message: "That comment could not be posted. Check its length and formatting."
           }
         )}
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

  defp capability_samples do
    [
      %{
        index: "001",
        title: "Clear boundaries",
        tone: "accent",
        kind: :circles,
        image: nil,
        description: "Rules and shared edges give every region a deliberate place on the page.",
        href: "#foundations",
        action: "Explore primitives"
      },
      %{
        index: "002",
        title: "Common structure",
        tone: "surface",
        kind: :triangle,
        image: nil,
        description:
          "One set of components, assembled to suit each product. Replace the copy and illustration without rebuilding the card.",
        href: "#composition",
        action: "Explore composition"
      },
      %{
        index: "003",
        title: "Your imagery",
        tone: "surface",
        kind: :image,
        image: "/images/brand/regents-crown-flat-dark.svg",
        description:
          "Use an image and alternative text, or supply custom artwork in the media slot. Actions are optional and remain application-owned.",
        href: "#inventory",
        action: "Inspect component API"
      }
    ]
  end

  @doc "Configuration status for local reference pages; never returns configuration values."
  def privy_mode do
    config = Application.get_env(:ash_platform, :privy, [])

    cond do
      Application.get_env(:ash_platform, :privy_verifier, AshPlatform.Privy) != AshPlatform.Privy ->
        :fixture

      Enum.all?([:app_id, :verification_key], fn key ->
        value = Keyword.get(config, key)
        is_binary(value) && String.trim(value) != ""
      end) ->
        :configured

      true ->
        :unconfigured
    end
  end

  defp run_utility("privy_valid", _params), do: Utilities.privy(:valid)
  defp run_utility("privy_expired", _params), do: Utilities.privy(:expired)
  defp run_utility("privy_audience", _params), do: Utilities.privy(:audience)
  defp run_utility("address", params), do: Utilities.address(params["address"] || "")

  defp run_utility("amount", params),
    do: Utilities.amount(params["amount"] || "", params["decimals"] || "")

  defp run_utility("calldata", params),
    do: Utilities.calldata(params["address"] || "", params["amount"] || "")

  defp run_utility(_kind, _params), do: %{error: "Choose a listed utility."}
end
