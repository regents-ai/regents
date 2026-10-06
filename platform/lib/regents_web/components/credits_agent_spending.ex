defmodule RegentsWeb.CreditsAgentSpending do
  @moduledoc """
  What a person lets each of their linked agents spend from their Credits: on
  or off, the most per spend, a daily limit and the sites it may spend on.
  Spending starts off for every agent. Only regents.sh/account shows this; the
  Credits library saves it only for a person signed in there.

  The host passes `actor` (the signed-in person, `RegentCredits.Actor` with
  site "regents"), `agents` (`{wallet, name}` for each agent paired with the
  account) and `sites` (`{site, label}` pairs an agent may spend on).
  """
  use RegentsWeb, :live_component

  alias Regent.Primitives, as: P
  alias RegentCredits.AgentPermission
  alias RegentsWeb.FormErrors

  @impl true
  def mount(socket), do: {:ok, assign(socket, saved: nil)}

  @impl true
  def update(assigns, socket) do
    saved =
      Map.new(RegentCredits.agent_permissions!(actor: assigns.actor), &{&1.agent_address, &1})

    agents = Enum.map(assigns.agents, fn {wallet, name} -> {String.downcase(wallet), name} end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       agents: agents,
       forms:
         Map.new(agents, fn {agent, _name} ->
           {agent, form(assigns.actor, agent, saved[agent])}
         end)
     )}
  end

  @impl true
  def handle_event("validate", %{"agent" => agent, "permission" => params}, socket) do
    form =
      socket.assigns.forms
      |> Map.fetch!(agent)
      |> AshPhoenix.Form.validate(clean(params, agent, socket))

    {:noreply, socket |> put_form(agent, form) |> assign(saved: nil)}
  end

  def handle_event("save", %{"agent" => agent, "permission" => params}, socket) do
    form = Map.fetch!(socket.assigns.forms, agent)

    case AshPhoenix.Form.submit(form, params: clean(params, agent, socket)) do
      {:ok, permission} ->
        {:noreply,
         socket
         |> put_form(agent, form(socket.assigns.actor, agent, permission))
         |> assign(saved: agent)}

      {:error, form} ->
        {:noreply, socket |> put_form(agent, form) |> assign(saved: nil)}
    end
  end

  # The account and agent come from the page, never the form; sites only from the list offered.
  defp clean(params, agent, socket) do
    offered = Enum.map(socket.assigns.sites, &elem(&1, 0))

    Map.merge(params, %{
      "privy_user_id" => socket.assigns.actor.privy_user_id,
      "agent_address" => agent,
      "sites" => params |> Map.get("sites", []) |> Enum.filter(&(&1 in offered))
    })
  end

  defp form(actor, agent, saved) do
    AgentPermission
    |> AshPhoenix.Form.for_create(:set,
      actor: actor,
      as: "permission",
      params: %{
        "privy_user_id" => actor.privy_user_id,
        "agent_address" => agent,
        "enabled" => saved != nil and saved.enabled,
        "max_per_spend" => saved && saved.max_per_spend,
        "daily_limit" => saved && saved.daily_limit,
        "sites" => if(saved, do: saved.sites, else: [])
      }
    )
    |> to_form()
  end

  defp put_form(socket, agent, form),
    do: assign(socket, forms: Map.put(socket.assigns.forms, agent, to_form(form)))

  # A checked figure comes back from the form as a decimal.
  defp figure(%Decimal{} = figure), do: Decimal.to_string(figure, :normal)
  defp figure(figure), do: figure

  defp enabled?(form), do: form[:enabled].value in [true, "true"]
  defp sites(form), do: List.wrap(form[:sites].value)

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="credits-agents">
      <p :if={@agents == []}>
        No agents are paired with your account yet. Pair one under Your agents to let it spend.
      </p>
      <.form
        :for={{{agent, name}, index} <- Enum.with_index(@agents)}
        for={@forms[agent]}
        id={"#{@id}-#{index}"}
        class="credits-agent"
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
      >
        <input type="hidden" name="agent" value={agent} />
        <h4>{name} <code>{RegentFormat.short_address(agent)}</code></h4>
        <label class="credits-agent__switch">
          <input type="hidden" name={@forms[agent][:enabled].name} value="false" />
          <input
            type="checkbox"
            name={@forms[agent][:enabled].name}
            value="true"
            checked={enabled?(@forms[agent])}
          /> Can spend my Credits
        </label>
        <P.field
          :let={field}
          id={"#{@id}-#{index}-max"}
          label="Most per spend, in Credits"
          errors={FormErrors.messages(@forms[agent][:max_per_spend])}
        >
          <input
            id={field.id}
            name={@forms[agent][:max_per_spend].name}
            value={figure(@forms[agent][:max_per_spend].value)}
            inputmode="decimal"
            autocomplete="off"
            phx-debounce="300"
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          />
        </P.field>
        <P.field
          :let={field}
          id={"#{@id}-#{index}-daily"}
          label="Daily limit, in Credits"
          errors={FormErrors.messages(@forms[agent][:daily_limit])}
        >
          <input
            id={field.id}
            name={@forms[agent][:daily_limit].name}
            value={figure(@forms[agent][:daily_limit].value)}
            inputmode="decimal"
            autocomplete="off"
            phx-debounce="300"
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          />
          <:hint>Bids still held count until they come back.</:hint>
        </P.field>
        <fieldset>
          <legend>Sites it may spend on</legend>
          <label :for={{site, label} <- @sites}>
            <input
              type="checkbox"
              name={@forms[agent][:sites].name <> "[]"}
              value={site}
              checked={site in sites(@forms[agent])}
            />
            {label}
          </label>
        </fieldset>
        <P.button type="submit" phx-disable-with="Saving…">Save</P.button>
        <p :if={@saved == agent} role="status">Saved.</p>
      </.form>
    </div>
    """
  end
end
