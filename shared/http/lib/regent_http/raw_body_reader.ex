defmodule RegentHttp.RawBodyReader do
  @moduledoc """
  `Plug.Parsers` body reader that captures the raw request body.

  Reads the body in chunks, caps it at 1MB (or the parser `:length` option
  when smaller), and assigns the exact bytes to `conn.assigns.raw_body` so
  signature verification (SIWA envelopes, webhook signatures) can run over
  the bytes that were actually received. Oversized bodies return `{:more, ...}`
  without assigning a raw body, which `Plug.Parsers` turns into a
  request-too-large error.

  Wire it in the endpoint:

      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        body_reader: {RegentHttp.RawBodyReader, :read_body, []}
  """

  @max_body_bytes 1_000_000

  def read_body(conn, opts) do
    max_body_bytes = opts |> Keyword.get(:length) |> cap_body_length()

    opts =
      opts
      |> Keyword.put(:length, max_body_bytes)
      |> Keyword.update(:read_length, max_body_bytes, &min_positive(&1, max_body_bytes))

    read_body(conn, opts, max_body_bytes, [], 0)
  end

  defp read_body(conn, opts, max_body_bytes, chunks, bytes_read) do
    remaining_bytes = max_body_bytes - bytes_read

    case Plug.Conn.read_body(conn, Keyword.put(opts, :length, remaining_bytes)) do
      {:ok, chunk, conn} ->
        final_bytes_read = bytes_read + byte_size(chunk)

        if final_bytes_read > max_body_bytes do
          {:more, build_body([chunk | chunks]), conn}
        else
          body = build_body([chunk | chunks])
          conn = Plug.Conn.assign(conn, :raw_body, body)
          {:ok, body, conn}
        end

      {:more, chunk, conn} ->
        bytes_read = bytes_read + byte_size(chunk)
        chunks = [chunk | chunks]

        if bytes_read >= max_body_bytes do
          {:more, build_body(chunks), conn}
        else
          read_body(conn, opts, max_body_bytes, chunks, bytes_read)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_body(chunks) do
    chunks
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp cap_body_length(value) when is_integer(value) and value > 0,
    do: min(value, @max_body_bytes)

  defp cap_body_length(_value), do: @max_body_bytes

  defp min_positive(value, max) when is_integer(value) and value > 0,
    do: min(value, max)

  defp min_positive(_value, max), do: max
end
