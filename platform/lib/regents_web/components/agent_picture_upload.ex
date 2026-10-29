defmodule RegentsWeb.AgentPictureUpload do
  @moduledoc """
  The picture beside one of a person’s agents, on regents.sh/account. The
  person chooses a PNG, JPEG or WebP of up to 5 MB and saves it, re-made as the
  small square kept for the agent (`Regents.AgentPicture`), or removes the one
  saved. Every Regent site shows it beside what the agent posts.

  The host passes `account` (the signed-in account), its `session_lease` as
  `lease`, and `agent` (the person's `RegentAgents.PairedAgent`, with
  `picture_updated_at` loaded). The shared agents library announces each
  change, and the page reads the agent again, so the picture shown is always
  the saved one.
  """
  use RegentsWeb, :live_component

  alias Regent.Primitives, as: P
  alias RegentAgents.Person
  alias Regents.AgentPicture
  alias RegentsWeb.AgentPictureController

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> RegentsWeb.Live.Session.check_component_lease(&take_account/2)
     |> allow_upload(:picture,
       accept: ~w(.png .jpg .jpeg .webp),
       max_entries: 1,
       max_file_size: AgentPicture.max_upload(),
       auto_upload: true
     )
     |> assign(notice: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :lease, :agent]))
     |> take_account(assigns.account)}
  end

  # The account as the page gave it, or as it reads now before each event
  # (`RegentsWeb.Live.Session.check_component_lease/2`).
  defp take_account(socket, account),
    do: assign(socket, actor: %Person{privy_user_id: account.privy_user_id})

  @impl true
  def handle_event("choose", _params, socket) do
    # A file refused before it uploads says why and makes way for the next one.
    socket =
      Enum.reduce(socket.assigns.uploads.picture.entries, socket, fn entry, socket ->
        case upload_errors(socket.assigns.uploads.picture, entry) do
          [] ->
            assign(socket, notice: nil)

          [error | _more] ->
            socket
            |> cancel_upload(:picture, entry.ref)
            |> assign(notice: {:alert, refused(error)})
        end
      end)

    {:noreply, socket}
  end

  def handle_event("cancel", %{"ref" => ref}, socket),
    do: {:noreply, socket |> cancel_upload(:picture, ref) |> assign(notice: nil)}

  def handle_event("save", _params, socket) do
    case uploaded_entries(socket, :picture) do
      {[_entry], []} ->
        {:noreply, save(socket)}

      _not_ready ->
        {:noreply, assign(socket, notice: {:alert, "Wait for the picture to finish uploading."})}
    end
  end

  def handle_event("remove", _params, socket) do
    notice =
      case RegentAgents.remove_agent_picture(socket.assigns.agent.id,
             actor: socket.assigns.actor
           ) do
        :ok ->
          {:status, "Picture removed."}

        {:error, _error} ->
          {:alert, "The picture couldn’t be removed. Nothing changed. Try again."}
      end

    {:noreply, assign(socket, notice: notice)}
  end

  # The path is LiveView's own temporary file for this upload, never a name from the browser.
  # sobelow_skip ["Traversal.FileModule"]
  defp save(socket) do
    [made] =
      consume_uploaded_entries(socket, :picture, fn %{path: path}, _entry ->
        {:ok, AgentPicture.make(File.read!(path))}
      end)

    notice =
      with {:ok, webp} <- made,
           {:ok, _picture} <-
             RegentAgents.set_agent_picture(socket.assigns.agent.id, webp,
               actor: socket.assigns.actor
             ) do
        {:status, "Picture saved."}
      else
        {:error, reason} when is_atom(reason) -> {:alert, refused(reason)}
        {:error, _error} -> {:alert, "The picture couldn’t be saved. Nothing changed. Try again."}
      end

    assign(socket, notice: notice)
  end

  defp refused(reason) when reason in [:too_large, :too_big],
    do: "That picture is too large. Choose one up to 5 MB."

  defp refused(reason) when reason in [:not_accepted, :not_a_picture],
    do: "Choose a PNG, JPEG or WebP picture."

  defp refused(:too_detailed), do: "That picture is too detailed; try another."
  defp refused(_reason), do: "The picture couldn’t upload. Try again."

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="account-agent-picture" aria-labelledby={"#{@id}-title"}>
      <h3 id={"#{@id}-title"}>Picture</h3>
      <form id={"#{@id}-form"} phx-change="choose" phx-submit="save" phx-target={@myself}>
        <div class="account-agent-picture__row">
          <div class="account-agent-picture__frame">
            <%= case @uploads.picture.entries do %>
              <% [entry | _] -> %>
                <.live_img_preview entry={entry} alt="" />
              <% [] -> %>
                <img
                  :if={picture_path(@agent)}
                  src={picture_path(@agent)}
                  alt={"#{@agent.name}’s picture"}
                />
                <Regent.Account.agent_mark
                  :if={is_nil(picture_path(@agent))}
                  kind={to_string(@agent.harness)}
                />
            <% end %>
          </div>
          <div class="account-agent-picture__actions">
            <p>PNG, JPEG or WebP, up to 5 MB. Shown beside what {@agent.name} posts.</p>
            <%= case @uploads.picture.entries do %>
              <% [entry | _] -> %>
                <div class="account-agent-picture__buttons">
                  <P.button type="submit" phx-disable-with="Saving…">Save picture</P.button>
                  <P.button
                    type="button"
                    variant="quiet"
                    phx-click="cancel"
                    phx-value-ref={entry.ref}
                    phx-target={@myself}
                  >
                    Cancel
                  </P.button>
                </div>
              <% [] -> %>
                <div class="account-agent-picture__buttons">
                  <label
                    for={@uploads.picture.ref}
                    class="rg-button rg-button--secondary account-agent-picture__choose"
                  >
                    <span class="rg-button__label">
                      {if picture_path(@agent),
                        do: "Choose another picture",
                        else: "Choose a picture"}
                    </span>
                  </label>
                  <P.button
                    :if={picture_path(@agent)}
                    type="button"
                    variant="quiet"
                    phx-click="remove"
                    phx-target={@myself}
                    data-confirm={"Remove #{@agent.name}’s picture?"}
                  >
                    Remove picture
                  </P.button>
                </div>
            <% end %>
            <.live_file_input upload={@uploads.picture} class="visually-hidden" />
          </div>
        </div>
      </form>
      <p
        id={"#{@id}-notice"}
        class="account-agent-picture__notice"
        role={notice_role(@notice)}
        aria-live="polite"
      >
        {notice_text(@notice)}
      </p>
    </section>
    """
  end

  defp picture_path(agent),
    do: AgentPictureController.path(agent.wallet, agent.picture_updated_at)

  defp notice_role({:alert, _text}), do: "alert"
  defp notice_role(_notice), do: "status"

  defp notice_text({_role, text}), do: text
  defp notice_text(nil), do: nil
end
