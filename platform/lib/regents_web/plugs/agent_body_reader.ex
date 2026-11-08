defmodule RegentsWeb.Plugs.AgentBodyReader do
  @moduledoc """
  Keeps the exact bytes of every body the API takes, so the sign-in service can
  check them against the request's signature (`RegentsWeb.Plugs.PairedAgent`,
  `RegentAgents.HTTP`): any of them may come from an agent. The pages' own form
  bodies are read as before.
  """

  # The largest body the API takes is a private profile, which
  # `RegentIdentity.BodyReader` caps at the same size.
  @limit 8192

  def read_body(conn, opts) do
    if signed?(conn),
      do: Siwa.AgentAuthPlug.read_body(conn, opts, @limit),
      else: RegentIdentity.BodyReader.read_body(conn, opts)
  end

  defp signed?(%{method: method, path_info: ["api" | _rest]}) when method in ["POST", "PATCH"],
    do: true

  defp signed?(_conn), do: false
end
