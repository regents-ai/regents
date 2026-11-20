defmodule RegentsWeb.Keyfleet.RouteCatalog.Entry do
  @moduledoc false
  @enforce_keys [:route_id, :path_pattern, :parameter_schema]
  defstruct @enforce_keys
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
  @enforce_keys [:route_id, :destination, :app_id, :background_slot, :sidebar_model]
  defstruct @enforce_keys
end
