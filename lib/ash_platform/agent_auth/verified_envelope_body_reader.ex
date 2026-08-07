defmodule AshPlatform.AgentAuth.VerifiedEnvelopeBodyReader do
  @moduledoc false

  import Plug.Conn, only: [assign: 3]

  @maximum_body_bytes 65_536
  @notebook_maximum_body_bytes 4_194_304

  def read_body(%{method: "POST", path_info: path_info} = conn, opts) do
    case body_limit(path_info) do
      nil -> Plug.Conn.read_body(conn, opts)
      limit -> read_bounded_body(conn, opts, limit)
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  defp body_limit(["api", "techtree", "v1", "nodes", _id, "evidence-state"]),
    do: @maximum_body_bytes

  defp body_limit(["api", "techtree", "v1", "nodes", _id, "notebook-artifact"]),
    do: @notebook_maximum_body_bytes

  defp body_limit(["api", "techtree", "v1", "nodes"]), do: @maximum_body_bytes
  defp body_limit(_path_info), do: nil

  defp read_bounded_body(conn, opts, limit) do
    opts = Keyword.merge(opts, length: limit, read_length: limit)

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
end
