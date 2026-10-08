defmodule RegentAgents.Test.Router do
  @moduledoc "A site that mounts the agent requests the way a Phoenix endpoint does."
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason,
    body_reader: {__MODULE__, :read_body, []},
    pass: ["*/*"]
  )

  plug(:match)
  plug(:dispatch)

  forward("/api/agents/v1", to: RegentAgents.HTTP)

  def read_body(conn, opts), do: Siwa.AgentAuthPlug.read_body(conn, opts, 4096)
end
