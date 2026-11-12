defmodule RegentsWeb.AdminMessagesLive do
  @moduledoc """
  The messages agents and people left for the site's team (`Regents.Messages`),
  newest first, 50 a page, for the site's admins only: the route sits behind
  the same check as the saved errors (`RegentsWeb.ErrorsAdmin`), which hands
  the page its admin actor, and the read's own policy asks again
  (`Regents.Checks.Admin`). `?after=` holds the cursor of the page before.
  """

  use RegentsWeb, :live_view

  alias Regent.Primitives
  alias Regents.Messages

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Messages",
       page_description: "Messages agents and people left for the Regents team."
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = if cursor = params["after"], do: [after: cursor], else: []

    {:noreply,
     assign(socket, :messages, Messages.list_messages(actor: socket.assigns.admin, page: page))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rl-root legal-root rg-sheet rg-frame admin-messages">
      <main class="legal-page">
        <h1>Messages</h1>
        <Primitives.notice :if={match?({:error, _}, @messages)} tone="error">
          The messages couldn’t be read. Refresh the page to try again.
        </Primitives.notice>
        <Primitives.empty_state :if={match?({:ok, %{results: []}}, @messages)} title="No messages">
          Messages agents and people leave for the team show here.
        </Primitives.empty_state>
        <%= with {:ok, page} <- @messages do %>
          <ol id="admin-messages" class="admin-messages__list">
            <li :for={message <- page.results} id={"message-#{message.id}"}>
              <dl class="admin-messages__meta">
                <div>
                  <dt>Topic</dt>
                  <dd><code>{message.topic}</code></dd>
                </div>
                <div>
                  <dt>From</dt>
                  <dd>
                    <bdi>{message.sender_name}</bdi>
                    <span :if={message.agent_wallet_address}>
                      · Agent
                      <Primitives.address
                        id={"message-#{message.id}-agent"}
                        address={message.agent_wallet_address}
                      />
                    </span>
                  </dd>
                </div>
                <div>
                  <dt>Sent</dt>
                  <dd>
                    <time datetime={DateTime.to_iso8601(message.inserted_at)}>
                      {Calendar.strftime(message.inserted_at, "%-d %b %Y, %H:%M UTC")}
                    </time>
                  </dd>
                </div>
                <div :if={message.reply_to}>
                  <dt>Reply to</dt>
                  <dd><bdi>{message.reply_to}</bdi></dd>
                </div>
              </dl>
              <p class="admin-messages__body">{message.body}</p>
            </li>
          </ol>
          <.link
            :if={page.more?}
            patch={"?after=" <> List.last(page.results).__metadata__.keyset}
            class="rg-button rg-button--secondary"
          >
            Older
          </.link>
        <% end %>
      </main>
    </div>
    """
  end
end
