defmodule RegentsWeb.Plugs.AgentBodyReader do
  @moduledoc """
  Keeps the exact bytes of every body the API and the hosted MCP server take, so
  the sign-in service can check them against the request's signature
  (`RegentsWeb.Plugs.PairedAgent`, `RegentAgents.HTTP`): any of them may come
  from an agent. The pages' own form bodies are read as before.
  """

  # The largest body the API takes is a private profile, which
  # `RegentIdentity.BodyReader` caps at the same size.
  @limit 8192
  # One MCP call carries its JSON-RPC envelope around the tool's input.
  @mcp_limit 65_536

  def read_body(%{method: "POST", path_info: ["mcp"]} = conn, opts),
    do: Siwa.AgentAuthPlug.read_body(conn, opts, @mcp_limit)

  def read_body(conn, opts) do
    if signed?(conn),
      do: Siwa.AgentAuthPlug.read_body(conn, opts, @limit),
      else: RegentIdentity.BodyReader.read_body(conn, opts)
  end

  defp signed?(%{method: method, path_info: ["api" | _rest]}) when method in ["POST", "PATCH"],
    do: true

  defp signed?(_conn), do: false
end
