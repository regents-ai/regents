defmodule RegentsWeb.Autolaunch.Components.XConnections do
  @moduledoc """
  A creator's connected accounts as one list of like rows: each row is the
  account's picture or mark, its kind, the account itself (or "Optional · not
  connected"), and its link or button on the right. X connections are managed
  on `/account/connections` in a new tab; open pages update live over Ash
  PubSub as soon as the account connects or disconnects there.
  """
  use Phoenix.Component
  use RegentsWeb, :verified_routes

  import RegentsWeb.Autolaunch.Components.LinkIcon

  attr :id, :string, required: true
  attr :x_identity, :map, default: nil, doc: "the account's verified `:x` LinkedIdentity, if any"

  attr :connections, :list,
    default: [],
    doc: "legacy verified XConnection rows, read-only fallback"

  slot :inner_block, doc: "more `connection/1` rows after X"

  def x_connections(assigns) do
    by_role = Map.new(assigns.connections, &{&1.role, &1})

    assigns =
      assign(assigns,
        x_account: connected(assigns.x_identity) || connected(by_role[:profile]),
        company_x: connected(by_role[:company])
      )

    ~H"""
    <div id={@id} class="connections">
      <ul class="connections__list">
        <.connection
          id={"#{@id}-x"}
          label="X"
          icon={:x}
          avatar={@x_account && Map.get(@x_account, :avatar_url)}
          name={@x_account && (@x_account.display_name || "@#{@x_account.username}")}
          href={@x_account && "https://x.com/#{URI.encode_www_form(@x_account.username)}"}
          detail={@x_account && "@#{@x_account.username}"}
        >
          <:actions>
            <a
              href={~p"/account/connections"}
              target="_blank"
              rel="noopener noreferrer"
              class="rg-button rg-button--secondary"
            >
              <span class="rg-button__label">{if @x_account, do: "Manage", else: "Connect"}</span>
            </a>
          </:actions>
        </.connection>
        <.connection
          :if={@company_x}
          id={"#{@id}-company"}
          label="Company X"
          icon={:x}
          avatar={Map.get(@company_x, :avatar_url)}
          name={@company_x.display_name || "@#{@company_x.username}"}
          href={"https://x.com/#{URI.encode_www_form(@company_x.username)}"}
          detail={"@#{@company_x.username}"}
        />
        {render_slot(@inner_block)}
      </ul>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :icon, :atom, required: true, values: [:x, :github, :ens]
  attr :avatar, :string, default: nil
  attr :name, :string, default: nil, doc: "the account's name, or nil while not connected"
  attr :href, :string, default: nil
  attr :detail, :string, default: nil, doc: "a second line under the name, such as a handle"
  attr :rest, :global
  slot :actions
  slot :below, doc: "a full-width part under the row, such as a form"

  @doc "One connected account in the list's shared layout."
  def connection(assigns) do
    ~H"""
    <li class="connection" {@rest}>
      <span class="connection__mark">
        <%!-- X's picture host refuses requests that name another site as the referrer. --%>
        <img
          :if={@avatar}
          src={@avatar}
          alt=""
          width="40"
          height="40"
          referrerpolicy="no-referrer"
        />
        <.link_icon :if={!@avatar} kind={@icon} />
      </span>
      <span class="connection__text">
        <strong>{@label}</strong>
        <a :if={@name && @href} href={@href} target="_blank" rel="noreferrer">{@name}</a>
        <span :if={@name && !@href}>{@name}</span>
        <small :if={@name && @detail}>{@detail}</small>
        <small :if={!@name}>Optional · not connected</small>
      </span>
      <span class="connection__actions">{render_slot(@actions)}</span>
      {render_slot(@below)}
    </li>
    """
  end

  defp connected(%{verified_at: %DateTime{}, username: username} = connection)
       when is_binary(username) and username != "",
       do: connection

  defp connected(_connection), do: nil
end
