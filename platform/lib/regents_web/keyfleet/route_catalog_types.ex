defmodule RegentsWeb.Keyfleet.RouteCatalog.Entry do
  @moduledoc false
  @enforce_keys [:path_pattern, :live_action, :parameter_schema, :reserved_values, :route_spec_id]
  # `fleet_id` is the fleet whose page it is, on a fleet's own pages.
  defstruct @enforce_keys ++ [fleet_id: nil]
end

defmodule RegentsWeb.Keyfleet.RouteCatalog.SidebarModel do
  @moduledoc false
  @enforce_keys [:id, :targets]
  defstruct @enforce_keys
end

defmodule RegentsWeb.Keyfleet.RouteCatalog.RouteTarget do
  @moduledoc false
  @enforce_keys [:route_id, :label, :path]
  defstruct @enforce_keys
end

defmodule RegentsWeb.Keyfleet.RouteCatalog.Spec do
  @moduledoc false
  @enforce_keys [
    :route_id,
    :destination,
    :fleet_id,
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
