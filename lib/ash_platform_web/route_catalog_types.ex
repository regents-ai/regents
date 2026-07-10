defmodule AshPlatformWeb.RouteCatalog.Entry do
  @moduledoc false
  @enforce_keys [:path_pattern, :live_action, :parameter_schema, :reserved_values, :route_spec_id]
  defstruct @enforce_keys
end

defmodule AshPlatformWeb.RouteCatalog.AppTarget do
  @moduledoc false
  @enforce_keys [:app_id, :label, :path]
  defstruct @enforce_keys
end

defmodule AshPlatformWeb.RouteCatalog.SidebarModel do
  @moduledoc false
  @enforce_keys [:id, :targets]
  defstruct @enforce_keys
end

defmodule AshPlatformWeb.RouteCatalog.RouteTarget do
  @moduledoc false
  @enforce_keys [:route_id, :label, :path]
  defstruct @enforce_keys
end

defmodule AshPlatformWeb.RouteCatalog.FormationPanelTarget do
  @moduledoc false
  @enforce_keys [:panel, :label]
  defstruct @enforce_keys
end

defmodule AshPlatformWeb.RouteCatalog.TreeTarget do
  @moduledoc false
  @enforce_keys [:tree_slug, :label, :path, :presentations]
  defstruct @enforce_keys
end

defmodule AshPlatformWeb.RouteCatalog.ViewerProfileTarget do
  @moduledoc false
  @enforce_keys [:label]
  defstruct @enforce_keys
end

defmodule AshPlatformWeb.RouteCatalog.Spec do
  @moduledoc false
  @enforce_keys [
    :route_id,
    :destination,
    :app_id,
    :app_display_label,
    :page_display_label,
    :canonical_root,
    :sidebar_model,
    :header_controls,
    :search_kind,
    :background_slot,
    :content_transition_kind,
    :scroll_policy,
    :local_state
  ]
  defstruct @enforce_keys
end
