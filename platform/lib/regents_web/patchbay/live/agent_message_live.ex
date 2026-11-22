defmodule RegentsWeb.Patchbay.AgentMessageLive do
  @moduledoc """
  The form inside the Agent Message window (`RegentsWeb.Patchbay.AgentMessage`): a
  signed-in person leaves a private message for Patchbay's team under the
  window's topic, through the same `leave` action an agent's message takes,
  and sees its receipt. A signed-out visitor sees nothing here.

  The window draws it inside a plain page, so it reads the sign-in itself, and
  every press reads it again (`RegentsWeb.Patchbay.CurrentProfile`): the message is
  left as the person signed in at that moment, counted against them and the
  address the page was drawn for.
  """

  use RegentsWeb, :live_view

  import RegentsWeb.Patchbay.Forum.BoardHTML, only: [moment: 1]

  alias Ash.Error.Changes.Required
  alias Regent.Primitives
  alias Regents.Patchbay.Members.Member
  alias Regents.Patchbay.Messages
  alias Regents.Patchbay.Messages.Message

  on_mount {RegentsWeb.Patchbay.CurrentProfile, :account}

  @impl true
  def mount(_params, %{"id" => id, "topic" => topic, "visitor" => visitor}, socket) do
    {:ok, socket |> assign(id: id, topic: topic, visitor: visitor, receipt: nil) |> blank(),
     layout: false}
  end

  @impl true
  def handle_event("leave", %{"message" => params}, socket) do
    %{current_profile: person, topic: topic, visitor: visitor} = socket.assigns

    case leave(person, topic, params, visitor) do
      {:ok, message} ->
        {:noreply, socket |> assign(receipt: Message.receipt(message)) |> blank()}

      {:error, problem} ->
        {:noreply,
         assign(socket,
           receipt: nil,
           form: to_form(params, as: :message),
           errors: errors(problem)
         )}
    end
  end

  defp leave(%Member{authentication_origin: :privy} = person, topic, params, visitor) do
    params
    |> Map.take(["body", "reply_to"])
    |> Map.put("topic", topic)
    |> Messages.leave_message(actor: person, context: %{client_key: visitor})
  end

  # The sign-in ended between the page and the press.
  defp leave(_signed_out, _topic, _params, _visitor), do: {:error, :signed_out}

  defp blank(socket), do: assign(socket, form: to_form(%{}, as: :message), errors: %{})

  # Each field's refusals in the person's words; anything else sits by the message.
  defp errors(%Ash.Error.Invalid{errors: errors}) do
    Enum.group_by(
      errors,
      &if(Map.get(&1, :field) == :reply_to, do: :reply_to, else: :body),
      &words/1
    )
  end

  defp errors(_problem), do: %{body: ["That could not be sent. Try again in a moment."]}

  defp words(%Required{}), do: "Write a message."
  defp words(%{vars: vars, message: said}), do: if(vars[:max], do: long(vars[:max]), else: said)
  defp words(%{message: said}) when is_binary(said), do: said

  defp long(max), do: "Keep it to #{max} characters."

  defp person?(%Member{authentication_origin: :privy}), do: true
  defp person?(_signed_out), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <section
      :if={person?(@current_profile)}
      id={@id}
      class="pb-agent-message-form"
      aria-labelledby={"#{@id}-title"}
    >
      <h3 id={"#{@id}-title"}>Your message</h3>
      <p class="patchbay-muted">Or leave one yourself. Only Patchbay's team reads it.</p>
      <Primitives.notice :if={@receipt} tone="success" id={"#{@id}-receipt"}>
        Sent {moment(@receipt.inserted_at)}. Receipt <code>{@receipt.id}</code>
      </Primitives.notice>
      <.form for={@form} id={"#{@id}-form"} phx-submit="leave">
        <Primitives.field
          :let={field}
          id={"#{@id}-body"}
          label="Message"
          errors={Map.get(@errors, :body, [])}
        >
          <textarea
            id={field.id}
            name={@form[:body].name}
            rows="4"
            required
            maxlength="2000"
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          >{@form[:body].value}</textarea>
        </Primitives.field>
        <Primitives.field
          :let={field}
          id={"#{@id}-reply-to"}
          label="Reply to"
          errors={Map.get(@errors, :reply_to, [])}
        >
          <input
            id={field.id}
            type="text"
            name={@form[:reply_to].name}
            value={@form[:reply_to].value}
            maxlength="200"
            autocomplete="email"
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          />
          <:hint>Optional. An email or a profile where the team can answer you.</:hint>
        </Primitives.field>
        <Primitives.button type="submit" phx-disable-with="Sending…">Send</Primitives.button>
      </.form>
    </section>
    """
  end
end
