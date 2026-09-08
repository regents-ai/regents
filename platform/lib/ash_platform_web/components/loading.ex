defmodule AshPlatformWeb.Components.Loading do
  @moduledoc "Layout-preserving placeholders for independently loaded page regions."
  use Phoenix.Component

  attr :kind, :string, default: "line", values: ~w(line title metric control inline)

  def skeleton(assigns) do
    ~H"""
    <span class={["loading-skeleton", "loading-skeleton--#{@kind}"]} aria-hidden="true"></span>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :labels, :list, default: []
  attr :class, :string, default: nil
  attr :loading, :boolean, default: true

  def panel(assigns) do
    ~H"""
    <div
      id={@id}
      class={["loading-panel rg-panel rg-panel--surface rg-panel__body", @class]}
      role="status"
      aria-busy={to_string(@loading)}
    >
      <h3>{@label}</h3>
      <p class="visually-hidden">{if @loading, do: "Loading data.", else: "Data unavailable."}</p>
      <dl :if={@labels != []} class="loading-metrics">
        <div :for={label <- @labels}>
          <dt>{label}</dt>
          <dd><.skeleton kind="metric" /></dd>
        </div>
      </dl>
      <div :if={@labels == []} class="loading-lines">
        <.skeleton kind="title" />
        <.skeleton />
        <.skeleton />
        <.skeleton kind="control" />
      </div>
    </div>
    """
  end
end
