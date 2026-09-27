defmodule RegentsWeb.RouteCatalog.Entry do
  @moduledoc false
  @enforce_keys [:path_pattern, :live_action, :parameter_schema, :reserved_values, :route_spec_id]
  defstruct @enforce_keys
end

defmodule RegentsWeb.RouteCatalog.SidebarModel do
  @moduledoc false
  @enforce_keys [:id, :targets]
  defstruct @enforce_keys
end

defmodule RegentsWeb.RouteCatalog.RouteTarget do
  @moduledoc false
  @enforce_keys [:route_id, :label, :path]
  defstruct @enforce_keys
end

defmodule RegentsWeb.RouteCatalog.ViewerProfileTarget do
  @moduledoc false
  @enforce_keys [:label]
  defstruct @enforce_keys
end

defmodule RegentsWeb.RouteCatalog.SidebarHeading do
  @moduledoc false
  @enforce_keys [:label]
  defstruct @enforce_keys
end

defmodule RegentsWeb.RouteCatalog.Spec do
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
    :background_slot,
    :scroll_policy,
    :local_state
  ]
  defstruct @enforce_keys
end
