defmodule AshPlatformWeb.Components.VerifiedConnections do
  @moduledoc false

  use Phoenix.Component

  alias AshPlatform.Accounts.LinkedIdentity.Providers

  attr :id, :string, required: true
  attr :identities, :list, default: []
  attr :notice, :map, default: nil
  attr :authenticated, :boolean, default: true
  attr :title, :string, default: "Verified connections"
  attr :description, :string, default: "Connect accounts that help people recognize your work."
  attr :kicker, :string, default: nil
  attr :class, :string, default: nil

  def verified_connections(assigns) do
    assigns =
      assigns
      |> assign(:providers, Providers.all())
      |> assign(:identities_by_provider, Map.new(assigns.identities, &{&1.provider, &1}))

    ~H"""
    <section
      id={@id}
      class={["verified-connections", @class]}
      aria-labelledby={"#{@id}-title"}
      phx-hook="VerifiedConnections"
    >
      <div>
        <p :if={@kicker} class="autolaunch-kicker">{@kicker}</p>
        <h2 id={"#{@id}-title"}>{@title}</h2>
        <p>{@description}</p>
        <p
          :if={@notice}
          class={[
            "verified-connections__notice",
            @notice.tone == :error && "verified-connections__notice--error"
          ]}
          role={if(@notice.tone == :error, do: "alert", else: "status")}
        >
          {@notice.message}
        </p>
      </div>

      <ul class="verified-connections__list">
        <li :for={entry <- @providers} id={"#{@id}-#{entry.provider}"}>
          <div>
            <strong>{entry.label}</strong>
            <.connection identity={@identities_by_provider[entry.provider]} />
          </div>

          <Regent.Primitives.button
            :if={@authenticated && is_nil(@identities_by_provider[entry.provider])}
            type="button"
            phx-click="request_verified_connection"
            phx-value-action="link"
            phx-value-provider={entry.provider}
          >
            Connect
          </Regent.Primitives.button>

          <Regent.Primitives.button
            :if={@authenticated && @identities_by_provider[entry.provider]}
            type="button"
            phx-click="request_verified_connection"
            phx-value-action="unlink"
            phx-value-provider={entry.provider}
          >
            Disconnect
          </Regent.Primitives.button>

          <Regent.Primitives.button
            :if={!@authenticated}
            type="button"
            data-account-target="sign-in"
          >
            Sign in to connect
          </Regent.Primitives.button>
        </li>
      </ul>
    </section>
    """
  end

  attr :identity, :map, default: nil

  defp connection(%{identity: nil} = assigns) do
    ~H"""
    <span>Not connected</span>
    """
  end

  defp connection(assigns) do
    assigns =
      assign(assigns,
        handle: Providers.handle(assigns.identity),
        profile_url: Providers.profile_url(assigns.identity.provider, assigns.identity.username)
      )

    ~H"""
    <a :if={@profile_url && @handle} href={@profile_url} target="_blank" rel="noreferrer">
      {@handle}
    </a>
    <span :if={!(@profile_url && @handle)}>
      {@identity.display_name || @handle || "Connected"}
    </span>
    """
  end
end
