defmodule RegentIdentity.BodyReader do
  @moduledoc "Caps private profile JSON before a consuming endpoint parses it."

  def read_body(%{request_path: path} = conn, options)
      when path in ["/api/v1/profile", "/api/v1/profile/sync"] do
    options = options |> Keyword.put(:length, 8192) |> Keyword.put(:read_length, 8193)
    Plug.Conn.read_body(conn, options)
  end

  def read_body(conn, options), do: Plug.Conn.read_body(conn, options)
end
