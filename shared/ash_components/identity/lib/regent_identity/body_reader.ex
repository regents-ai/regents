defmodule RegentIdentity.BodyReader do
  @moduledoc "Caps private profile JSON before a consuming endpoint parses it."

  def read_body(%{path_info: ["api", "v1", "profile"]} = conn, options) do
    options = options |> Keyword.put(:length, 8192) |> Keyword.put(:read_length, 8193)
    Plug.Conn.read_body(conn, options)
  end

  def read_body(conn, options), do: Plug.Conn.read_body(conn, options)
end
