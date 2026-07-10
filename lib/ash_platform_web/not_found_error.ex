defmodule AshPlatformWeb.NotFoundError do
  @moduledoc false
  defexception message: "Not found", plug_status: 404

  defimpl Plug.Exception do
    def status(_exception), do: 404
    def actions(_exception), do: []
  end
end
