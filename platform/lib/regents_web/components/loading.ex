defmodule RegentsWeb.Components.Loading do
  @moduledoc """
  Layout-preserving placeholders for independently loaded page regions. A region
  whose read failed keeps the same layout and says so in words; a placeholder
  only ever stands for a read still on its way.
  """
  use Phoenix.Component
  alias RegentsWeb.TokenDisplay

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
      <p :if={@loading} class="visually-hidden">Loading data.</p>
      <dl :if={@labels != []} class="loading-metrics">
        <div :for={label <- @labels}>
          <dt>{label}</dt>
          <dd>
            <.skeleton :if={@loading} kind="metric" />
            <TokenDisplay.amount :if={!@loading} amount={:unavailable} />
          </dd>
        </div>
      </dl>
      <div :if={@labels == [] && @loading} class="loading-lines">
        <.skeleton kind="title" />
        <.skeleton />
        <.skeleton />
        <.skeleton kind="control" />
      </div>
      <p :if={@labels == [] && !@loading}><TokenDisplay.amount amount={:unavailable} /></p>
    </div>
    """
  end
end
