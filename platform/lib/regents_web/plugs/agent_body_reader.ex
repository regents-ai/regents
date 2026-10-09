defmodule RegentsWeb.Plugs.AgentBodyReader do
  @moduledoc """
  Keeps the exact bytes of an agent's request to `/api/agents` or `/api/agent`, since its SIWA
  signature covers them and the parsed body cannot be turned back into them.
  """

  @maximum_bytes 4096

  def read_body(%{path_info: ["api", prefix | _]} = conn, options)
      when prefix in ["agents", "agent"],
      do: Siwa.AgentAuthPlug.read_body(conn, options, @maximum_bytes)

  def read_body(conn, options), do: RegentIdentity.BodyReader.read_body(conn, options)
end
