defmodule AshPlatformWeb.Components.Shell.Sidebar do
  @moduledoc false

  use Phoenix.Component

  alias AshPlatformWeb.RouteCatalog.{
    FormationPanelTarget,
    RouteTarget,
    TreeTarget,
    ViewerProfileTarget
  }

  attr(:route_spec, :map, required: true)
  attr(:presentation, :atom, required: true)
  attr(:formation_panel, :atom, required: true)
  attr(:viewer_profile_path, :string, default: nil)

  def sidebar(assigns) do
    ~H"""
    <nav id="shell-sidebar" class="shell-sidebar" aria-label="Context navigation">
      <ul>
        <li :for={target <- @route_spec.sidebar_model.targets}>
          <.sidebar_target
            target={target}
            route_spec={@route_spec}
            presentation={@presentation}
            formation_panel={@formation_panel}
            viewer_profile_path={@viewer_profile_path}
          />
        </li>
      </ul>
      <div class="shell-sidebar__ambient" aria-hidden="true"></div>
    </nav>
    """
  end

  attr(:target, :map, required: true)
  attr(:route_spec, :map, required: true)
  attr(:presentation, :atom, required: true)
  attr(:formation_panel, :atom, required: true)
  attr(:viewer_profile_path, :string, default: nil)

  defp sidebar_target(%{target: %RouteTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <.link
      patch={@target.path}
      data-sidebar-target={@target.route_id}
      aria-current={if @route_spec.route_id == @target.route_id, do: "page"}
    >
      {@target.label}
    </.link>
    """
  end

  defp sidebar_target(%{target: %TreeTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <div class="tree-target" data-tree={@target.tree_slug}>
      <.link
        patch={@target.path}
        data-sidebar-target={@target.tree_slug}
        aria-current={if @route_spec.destination == @target.path, do: "page"}
      >
        {@target.label}
      </.link>
      <span
        class="tree-target__presentations"
        role="group"
        aria-label={"#{@target.label} presentation"}
      >
        <.link
          :for={presentation <- @target.presentations}
          patch={@target.path}
          data-tree-presentation={presentation}
          data-tree-path={@target.path}
          aria-label={"#{@target.label} #{presentation}"}
          aria-current={
            if @route_spec.destination == @target.path && @presentation == presentation,
              do: "true"
          }
        >
          {presentation |> Atom.to_string() |> String.capitalize()}
        </.link>
      </span>
    </div>
    """
  end

  defp sidebar_target(%{target: %FormationPanelTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <button
      type="button"
      data-sidebar-target={@target.panel}
      data-formation-panel-choice={@target.panel}
      aria-pressed={to_string(@formation_panel == @target.panel)}
    >
      {@target.label}
    </button>
    """
  end

  defp sidebar_target(%{target: %ViewerProfileTarget{} = target} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <.link
      :if={@viewer_profile_path}
      patch={@viewer_profile_path}
      data-sidebar-target="profile"
      aria-current={if @route_spec.route_id == :regent_profile, do: "page"}
    >
      {@target.label}
    </.link>
    <span :if={!@viewer_profile_path} data-sidebar-target="profile" aria-disabled="true">
      {@target.label}
    </span>
    """
  end
end
