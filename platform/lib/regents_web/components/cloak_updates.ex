defmodule RegentsWeb.Components.CloakUpdates do
  @moduledoc """
  The Updates band on `/cloak/download`: someone who has just downloaded Cloak
  leaves an email address for news of its releases and features, through
  `Regents.Updates`' `subscribe` action, and the form gives way to a thank-you.
  The address is checked when the visitor leaves the field and again on the press.

  `RegentsWeb.CloakDownloadLive` passes the shell's `client_tag`, which the action
  counts tries against.
  """

  use RegentsWeb, :live_component

  alias Regent.Primitives
  alias Regents.Updates
  alias RegentsWeb.FormErrors

  @impl true
  def mount(socket), do: {:ok, assign(socket, done?: false)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :client_tag]))

    if Map.has_key?(socket.assigns, :form),
      do: {:ok, socket},
      else: {:ok, assign(socket, :form, new_form(socket.assigns.client_tag))}
  end

  @impl true
  def handle_event("validate", %{"updates" => params}, socket),
    do: {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}

  def handle_event("subscribe", %{"updates" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _subscriber} -> {:noreply, assign(socket, done?: true)}
      {:error, form} -> {:noreply, assign(socket, :form, form)}
    end
  end

  defp new_form(client_tag) do
    Updates.form_to_subscribe_to_updates(
      as: "updates",
      context: %{client_key: client_tag},
      prepare_params: fn params, _phase -> Map.put(params, "source", "cloak") end
    )
    |> to_form()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="cloak-updates" aria-labelledby={"#{@id}-title"}>
      <Regent.Structure.panel class="cloak-updates__panel rg-panel__body">
        <span class="cloak-updates__icon"><Regent.Icons.icon name="mail" /></span>
        <div class="cloak-updates__copy">
          <h2 id={"#{@id}-title"}>Updates</h2>
          <p>
            Occasional news on new releases and features. Your address is used only for Cloak news.
          </p>
        </div>
        <%!-- Always on the page, so a screen reader says the thanks as it appears. --%>
        <div role="status" class="cloak-updates__status">
          <p :if={@done?} id={"#{@id}-done"} class="cloak-updates__done">
            <Regent.Icons.icon name="mail-check" />
            <span>Thanks. You are on the list.</span>
          </p>
        </div>
        <.form
          :if={!@done?}
          for={@form}
          id={"#{@id}-form"}
          class="cloak-updates__form"
          novalidate
          phx-change="validate"
          phx-submit="subscribe"
          phx-target={@myself}
        >
          <Primitives.field
            :let={field}
            id={"#{@id}-address"}
            label="Email"
            class="cloak-updates__field"
            errors={FormErrors.messages(@form[:address])}
          >
            <input
              id={field.id}
              name={@form[:address].name}
              value={@form[:address].value}
              type="email"
              autocomplete="email"
              placeholder="Your email address"
              maxlength="254"
              phx-debounce="blur"
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by}
            />
          </Primitives.field>
          <Primitives.button type="submit" arrow={false} phx-disable-with="Sending…">
            Subscribe
          </Primitives.button>
        </.form>
      </Regent.Structure.panel>
    </section>
    """
  end
end
