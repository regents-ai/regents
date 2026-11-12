defmodule RegentsWeb.AdminPicturesLive do
  @moduledoc """
  The site's admins remove an agent's picture that breaks the rules; they never
  set or change one. The route sits behind the same check as the saved errors
  (`RegentsWeb.ErrorsAdmin`), which hands the page its admin actor and asks
  again before every press, and the removal's own policy asks once more
  (`RegentAgents.Checks.Admin`).
  """

  use RegentsWeb, :live_view

  alias Regent.Primitives
  alias Regents.WalletActions.Address
  alias RegentsWeb.AgentPictureController

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Pictures",
       page_description: "Remove an agent's picture that breaks the rules.",
       wallet: nil,
       picture: nil,
       errors: [],
       note: nil
     )}
  end

  @impl true
  def handle_event("find", %{"wallet" => wallet}, socket) do
    case wallet |> String.trim() |> Address.normalize() do
      {:ok, wallet} ->
        {:noreply,
         assign(socket, wallet: wallet, picture: picture(wallet), errors: [], note: nil)}

      :error ->
        {:noreply,
         assign(socket,
           wallet: nil,
           picture: nil,
           errors: ["Enter the agent's full 0x address."],
           note: nil
         )}
    end
  end

  def handle_event(
        "remove",
        _params,
        %{assigns: %{picture: %RegentAgents.AgentPicture{}}} = socket
      ) do
    team = %RegentAgents.Person{privy_user_id: socket.assigns.admin.privy_user_id, role: :admin}

    case RegentAgents.remove_agent_picture_by_team(socket.assigns.picture.paired_agent_id,
           actor: team
         ) do
      :ok ->
        {:noreply,
         assign(socket,
           picture: :none,
           note: {"success", "Picture removed. Its owner may choose another."}
         )}

      {:error, _error} ->
        {:noreply, assign(socket, note: {"error", "Nothing changed. Try again."})}
    end
  end

  # A press after the picture has gone, such as a second press on Remove.
  def handle_event("remove", _params, socket), do: {:noreply, socket}

  defp picture(wallet) do
    case RegentAgents.agent_picture(wallet) do
      {:ok, %RegentAgents.AgentPicture{} = picture} -> picture
      {:ok, nil} -> :none
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rl-root legal-root rg-sheet rg-frame admin-pictures">
      <main class="legal-page">
        <h1>Pictures</h1>
        <p>Remove an agent's picture that breaks the rules. Its owner may choose another.</p>
        <form id="admin-pictures-form" class="admin-pictures__form" phx-submit="find">
          <Primitives.field
            :let={field}
            id="admin-pictures-wallet"
            label="Agent address"
            errors={@errors}
          >
            <input
              id={field.id}
              name="wallet"
              autocomplete="off"
              spellcheck="false"
              required
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by}
            />
          </Primitives.field>
          <Primitives.button type="submit" variant="secondary">Find</Primitives.button>
        </form>
        <p :if={@picture == :none and is_nil(@note)} id="admin-pictures-none">
          No picture for <Primitives.address id="admin-pictures-none-address" address={@wallet} />.
        </p>
        <div
          :if={match?(%RegentAgents.AgentPicture{}, @picture)}
          id="admin-pictures-picture"
          class="admin-pictures__picture"
        >
          <img
            src={AgentPictureController.path(@wallet, @picture.updated_at)}
            alt="The agent's picture"
            width="128"
            height="128"
          />
          <Primitives.button
            type="button"
            variant="secondary"
            phx-click="remove"
            data-confirm="Remove this agent's picture?"
            data-confirm-action="Remove"
          >
            Remove
          </Primitives.button>
        </div>
        <Primitives.notice :if={@note} id="admin-pictures-note" tone={elem(@note, 0)}>
          {elem(@note, 1)}
        </Primitives.notice>
      </main>
    </div>
    """
  end
end
