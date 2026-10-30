defmodule RegentsWeb.Plugs.AgentBodyReader do
  @moduledoc """
  Keeps the exact bytes of an agent's request to `/api/agents`, `/api/agent` or the
  hosted MCP server, since its SIWA signature covers them and the parsed body
  cannot be turned back into them.
  """

  @maximum_bytes 4096

  # One MCP call carries its JSON-RPC envelope around the tool's input.
  @mcp_maximum_bytes 65_536

  def read_body(%{path_info: ["api", prefix | _]} = conn, options)
      when prefix in ["agents", "agent"],
      do: Siwa.AgentAuthPlug.read_body(conn, options, @maximum_bytes)

  def read_body(%{method: "POST", path_info: ["mcp"]} = conn, options),
    do: Siwa.AgentAuthPlug.read_body(conn, options, @mcp_maximum_bytes)

  def read_body(conn, options), do: RegentIdentity.BodyReader.read_body(conn, options)
end
