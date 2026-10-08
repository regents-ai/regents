defmodule RegentsWeb.Plugs.AgentBodyReader do
  @moduledoc """
  Keeps the exact bytes of an agent's request to `/api/agents`, since its SIWA
  signature covers them and the parsed body cannot be turned back into them.
  """

  @maximum_bytes 4096

  def read_body(%{path_info: ["api", "agents" | _]} = conn, options),
    do: Siwa.AgentAuthPlug.read_body(conn, options, @maximum_bytes)

  def read_body(conn, options), do: RegentIdentity.BodyReader.read_body(conn, options)
end
