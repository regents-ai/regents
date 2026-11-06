defmodule RegentsWeb.PicturesAdmin do
  @moduledoc """
  The site's admins remove an agent's picture that breaks the rules, at
  regents.sh/admin/pictures; they never set or change one. The host passes
  `account`, the signed-in account, and its `session_lease` as `lease`; the
  panel acts as a team `RegentAgents.Person` of it, which `RegentAgents`
  refuses to anyone not named in its `:admins` setting.
  """
  use RegentsWeb, :live_component

  alias Regent.Primitives, as: P
  alias RegentsWeb.AgentPictureController

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> RegentsWeb.Live.Session.check_component_lease(&take_account/2)
     |> assign(search: "", picture: nil, note: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :lease]))
     |> take_account(assigns.account)}
  end

  # The account as the page gave it, or as it reads now before each event
  # (`RegentsWeb.Live.Session.check_component_lease/2`).
  defp take_account(socket, account),
    do: assign(socket, team: %RegentAgents.Person{privy_user_id: account.privy_user_id, role: :admin})

  @impl true
  def handle_event("find_picture", %{"wallet" => wallet}, socket) do
    wallet = wallet |> String.trim() |> String.downcase()

    picture =
      case RegentAgents.agent_picture(wallet) do
        {:ok, %RegentAgents.AgentPicture{} = picture} -> picture
        _none -> :none
      end

    {:noreply, assign(socket, search: wallet, picture: picture, note: nil)}
  end

  def handle_event("remove_picture", _params, %{assigns: %{picture: picture}} = socket)
      when is_struct(picture, RegentAgents.AgentPicture) do
    case RegentAgents.remove_agent_picture_by_team(picture.paired_agent_id,
           actor: socket.assigns.team
         ) do
      :ok ->
        {:noreply,
         assign(socket, picture: :none, note: {:ok, "Picture removed. Its owner may choose another."})}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, assign(socket, note: {:error, "Only the site's admins can remove a picture."})}

      {:error, _error} ->
        {:noreply, assign(socket, note: {:error, "Nothing changed. Try again."})}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="pictures-admin">
      <form id={"#{@id}-form"} phx-submit="find_picture" phx-target={@myself}>
        <P.field :let={field} id={"#{@id}-wallet"} label="Agent address">
          <input id={field.id} name="wallet" value={@search} autocomplete="off" required />
        </P.field>
        <P.button type="submit" variant="secondary">Find</P.button>
      </form>
      <p :if={@picture == :none and is_nil(@note)} id={"#{@id}-none"}>
        No picture for <P.address id={"#{@id}-none-address"} address={@search} />
      </p>
      <div :if={is_struct(@picture, RegentAgents.AgentPicture)} class="pictures-admin__picture">
        <img
          id={"#{@id}-picture"}
          src={AgentPictureController.path(@search, @picture.updated_at)}
          alt="The agent's picture"
          width="128"
          height="128"
        />
        <P.button
          type="button"
          variant="secondary"
          phx-click="remove_picture"
          phx-target={@myself}
          data-confirm="Remove this agent's picture?"
        >
          Remove picture
        </P.button>
      </div>
      <P.notice :if={@note} tone={if elem(@note, 0) == :ok, do: "success", else: "error"}>
        {elem(@note, 1)}
      </P.notice>
    </div>
    """
  end
end
