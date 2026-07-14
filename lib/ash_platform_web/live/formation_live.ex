defmodule AshPlatformWeb.FormationLive do
  @moduledoc false
  use Phoenix.Component

  attr :account_control, AshPlatform.AccessContext.AccountControl, required: true
  attr :regent, :map, default: nil
  attr :regent_status, :atom, required: true
  attr :regent_notice, :map, default: nil
  attr :formation_fields, :map, required: true
  attr :cloud_runtime, :map, default: nil
  attr :cloud_status, :atom, required: true
  attr :cloud_notice, :map, default: nil

  def page(assigns) do
    ~H"""
    <section id="formation-lifecycle" class="formation-page">
      <section class="formation-panel" data-formation-panel-content="overview">
        <header class="formation-heading">
          <p class="formation-kicker">Formation</p>
          <h1>Form your Regent</h1>
          <p>
            Create and manage one Regent that brings together its cloud, Hermes skills, and
            prepaid operations.
          </p>
        </header>

        <div class="formation-account">
          <p :if={@account_control.kind == :sign_in}>
            Sign in to begin with one Regent tied to your account.
          </p>
          <div :if={@account_control.kind == :signed_in && @regent_status == :empty}>
            <p>Signed in as <strong>{@account_control.label}</strong>.</p>
            <h2>Form your one Regent</h2>
            <p>Choose the public name and URL that will represent it across Regent.</p>

            <form id="form-regent" phx-submit="form_regent" class="formation-form">
              <label>
                <span>Public name</span>
                <input
                  type="text"
                  name="regent[display_name]"
                  value={@formation_fields["display_name"]}
                  maxlength="80"
                  required
                  autocomplete="off"
                />
              </label>
              <label>
                <span>Profile URL</span>
                <span class="formation-slug-field">
                  <span>regents.sh/regents/</span>
                  <input
                    type="text"
                    name="regent[slug]"
                    value={@formation_fields["slug"]}
                    maxlength="63"
                    pattern="[a-z0-9]+(?:-[a-z0-9]+)*"
                    required
                    autocomplete="off"
                  />
                </span>
              </label>
              <button type="submit">Form Regent</button>
            </form>
          </div>

          <div :if={@account_control.kind == :signed_in && @regent}>
            <p>Signed in as <strong>{@account_control.label}</strong>.</p>
            <h2>{@regent.display_name} is formed</h2>
            <p>{@regent.summary || "Add a short public summary when you are ready."}</p>
            <.link patch={"/regents/#{@regent.slug}"}>View public profile</.link>

            <form id="update-regent-profile" phx-submit="update_regent_profile" class="formation-form">
              <label>
                <span>Public name</span>
                <input
                  type="text"
                  name="profile[display_name]"
                  value={@regent.display_name}
                  maxlength="80"
                  required
                />
              </label>
              <label>
                <span>Public summary</span>
                <textarea name="profile[summary]" maxlength="500">{@regent.summary}</textarea>
              </label>
              <label>
                <span>Public avatar image</span>
                <input
                  type="url"
                  name="profile[avatar_url]"
                  value={@regent.avatar_url}
                  maxlength="2048"
                  placeholder="https://…"
                />
              </label>
              <button type="submit">Save profile</button>
            </form>
          </div>

          <p
            :if={@regent_notice}
            class={"formation-notice formation-notice--#{@regent_notice.tone}"}
            role="status"
          >
            {@regent_notice.message}
          </p>
        </div>

        <ol class="formation-stages" aria-label="Formation lifecycle">
          <.stage number="01" title="Identity" copy="Name the Regent and establish its owner." />
          <.stage number="02" title="Cloud" copy="Provision and control its Sprite runtime." />
          <.stage number="03" title="Hermes" copy="Choose the skills and profiles it can use." />
          <.stage
            number="04"
            title="Billing"
            copy="Fund runtime and hosted AI use before work begins."
          />
        </ol>
      </section>

      <section class="formation-panel" data-formation-panel-content="cloud">
        <header class="formation-heading">
          <p class="formation-kicker">Formation · Cloud</p>
          <h1>Cloud</h1>
          <p>Your Regent runs in a dedicated Sprite that you can pause and resume.</p>
        </header>
        <.empty_state
          :if={@account_control.kind == :sign_in}
          title="Sign in to manage Cloud"
          copy="Your account owns the Regent and its Sprite runtime."
        />

        <.empty_state
          :if={@account_control.kind == :signed_in && is_nil(@regent)}
          title="Form your Regent first"
          copy="Cloud provisioning begins after this account has formed its one Regent."
        />

        <div
          :if={@account_control.kind == :signed_in && @regent && is_nil(@cloud_runtime)}
          class="formation-empty"
        >
          <h2>No Sprite connected</h2>
          <p>
            Provision one private Sprite for {@regent.display_name}. This creates the runtime
            container only; Hermes setup, service execution, and billing controls remain separate.
          </p>
          <button id="provision-cloud-runtime" type="button" phx-click="provision_cloud_runtime">
            Provision Sprite
          </button>
        </div>

        <section
          :if={@cloud_runtime}
          id="formation-cloud-runtime"
          class="formation-cloud-runtime"
          aria-labelledby="formation-cloud-runtime-title"
        >
          <div>
            <p class="formation-kicker">Verified provider state</p>
            <h2 id="formation-cloud-runtime-title">{@regent.display_name}</h2>
          </div>
          <dl>
            <div>
              <dt>Sprite</dt>
              <dd>{@cloud_runtime.sprite_name}</dd>
            </div>
            <div>
              <dt>Status</dt>
              <dd>{@cloud_runtime.provider_status}</dd>
            </div>
            <div>
              <dt>Protected URL</dt>
              <dd>{@cloud_runtime.url}</dd>
            </div>
            <div>
              <dt>Observed</dt>
              <dd>{Calendar.strftime(@cloud_runtime.observed_at, "%Y-%m-%d %H:%M UTC")}</dd>
            </div>
          </dl>
          <button id="refresh-cloud-runtime" type="button" phx-click="refresh_cloud_runtime">
            Refresh status
          </button>
        </section>

        <p
          :if={@cloud_notice}
          class={"formation-notice formation-notice--#{@cloud_notice.tone}"}
          role="status"
        >
          {@cloud_notice.message}
        </p>
      </section>

      <section class="formation-panel" data-formation-panel-content="hermes_skills">
        <header class="formation-heading">
          <p class="formation-kicker">Formation · Hermes</p>
          <h1>Hermes Skills</h1>
          <p>Choose the skills and working profiles available to Hermes on your Regent.</p>
        </header>
        <.empty_state
          title="Hermes is not connected"
          copy="Skills and profiles will appear after the Regent's runtime is ready."
        />
      </section>

      <section class="formation-panel" data-formation-panel-content="billing">
        <header class="formation-heading">
          <p class="formation-kicker">Formation · Billing</p>
          <h1>Billing</h1>
          <p>Prepaid credit funds Sprite runtime and hosted AI use from one balance.</p>
        </header>
        <.empty_state
          title="No prepaid balance yet"
          copy="Balance, top-up, and spend controls will appear when billing is connected."
        />
      </section>
    </section>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :copy, :string, required: true

  defp stage(assigns) do
    ~H"""
    <li>
      <span>{@number}</span>
      <div>
        <h2>{@title}</h2>
        <p>{@copy}</p>
      </div>
    </li>
    """
  end

  attr :title, :string, required: true
  attr :copy, :string, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="formation-empty">
      <h2>{@title}</h2>
      <p>{@copy}</p>
    </div>
    """
  end
end
