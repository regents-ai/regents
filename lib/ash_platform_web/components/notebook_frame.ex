defmodule AshPlatformWeb.Components.NotebookFrame do
  @moduledoc false
  use Phoenix.Component

  alias AshPlatform.Techtree.NotebookArtifact.Proof

  attr :artifact, :map, default: nil

  def frame(assigns) do
    assigns = assign(assigns, :runnable?, runnable?(assigns.artifact))

    ~H"""
    <section id="local-notebook" class="techtree-node-section techtree-notebook">
      <header class="techtree-notebook-header">
        <div>
          <p class="techtree-kicker">Local notebook</p>
          <h2>Runs on this device</h2>
        </div>
        <span :if={@artifact} class="techtree-notebook-runtime">Marimo {@artifact.marimo_version}</span>
      </header>

      <%= if @runnable? do %>
        <p class="techtree-notebook-copy">
          Explore this notebook with local browser compute. Your Regent session is not shared
          with the notebook.
        </p>
        <iframe
          id={"marimo-notebook-#{@artifact.id}"}
          class="techtree-notebook-frame"
          title="Interactive local notebook"
          src={@artifact.run_url}
          sandbox="allow-scripts allow-same-origin"
          credentialless={true}
          referrerpolicy="no-referrer"
          allow="camera 'none'; geolocation 'none'; microphone 'none'; payment 'none'"
          loading="lazy"
        ></iframe>
      <% else %>
        <p class="techtree-notebook-copy">
          This node does not include a browser-run notebook.
        </p>
      <% end %>
    </section>
    """
  end

  defp runnable?(nil), do: false
  defp runnable?(artifact), do: Proof.runnable?(artifact)
end
