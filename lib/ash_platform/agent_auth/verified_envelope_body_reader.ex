defmodule AshPlatform.AgentAuth.VerifiedEnvelopeBodyReader do
  @moduledoc false

  import Plug.Conn, only: [assign: 3]

  @maximum_body_bytes 65_536
  @publication_path "/api/techtree/v1/nodes"

  def read_body(%{method: "POST", request_path: @publication_path} = conn, opts) do
    opts = Keyword.merge(opts, length: @maximum_body_bytes, read_length: @maximum_body_bytes)

    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, assign(conn, :verified_envelope_raw_body, body)}

      {:more, _partial, conn} ->
        conn = assign(conn, :verified_envelope_body_error, :too_large)
        {:ok, "{}", conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)
end
