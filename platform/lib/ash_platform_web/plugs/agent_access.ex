defmodule AshPlatformWeb.Plugs.AgentAccess do
  @moduledoc "Negotiates explicit public documents, without opening application routes."
  import Plug.Conn
  alias AshPlatformWeb.PublicDocuments

  @formats [{"html", "text", "html"}, {"md", "text", "markdown"}, {"json", "application", "json"}]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = register_before_send(conn, &vary_accept/1)

    error_format =
      case conn.path_info do
        ["api" | _] -> "json"
        _ -> negotiate(conn, @formats) || "html"
      end

    conn = put_private(conn, :phoenix_format, error_format)
    document = if conn.method in ["GET", "HEAD"], do: PublicDocuments.document(conn.request_path)

    case document do
      nil -> conn
      document -> public_document(conn, document)
    end
  end

  defp public_document(conn, document) do
    case negotiate(conn, Enum.take(@formats, 2)) do
      "md" ->
        conn
        |> Phoenix.Controller.put_secure_browser_headers()
        |> put_resp_content_type("text/markdown")
        |> send_resp(200, document.markdown)
        |> halt()

      "html" ->
        conn

      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          406,
          "This document is available as text/html or text/markdown. See /llms.txt.\n"
        )
        |> halt()
    end
  end

  # A specific q=0 exclusion overrides a wildcard. Phoenix's browser-oriented
  # accepts/2 does not make that distinction, so it cannot select this variant.
  defp negotiate(conn, formats) do
    headers = get_req_header(conn, "accept")
    headers = if headers == [], do: ["*/*"], else: headers

    ranges =
      headers
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.flat_map(fn value ->
        case Plug.Conn.Utils.media_type(value) do
          {:ok, type, subtype, params} -> [{type, subtype, quality(params)}]
          :error -> []
        end
      end)

    formats
    |> Enum.with_index()
    |> Enum.map(fn {{format, type, subtype}, order} ->
      {specificity, quality} =
        ranges
        |> Enum.flat_map(fn
          {^type, ^subtype, q} -> [{2, q}]
          {^type, "*", q} -> [{1, q}]
          {"*", "*", q} -> [{0, q}]
          _ -> []
        end)
        |> Enum.max(fn -> {-1, 0.0} end)

      {quality, specificity, -order, format}
    end)
    |> Enum.filter(fn {quality, _, _, _} -> quality > 0 end)
    |> Enum.max(fn -> nil end)
    |> case do
      nil -> nil
      {_, _, _, format} -> format
    end
  end

  defp quality(params) do
    case Float.parse(Map.get(params, "q", "1")) do
      {q, ""} when q >= 0 and q <= 1 -> q
      _ -> 0.0
    end
  end

  defp vary_accept(conn) do
    values =
      conn
      |> get_resp_header("vary")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Kernel.++(["Accept"])
      |> Enum.uniq_by(&String.downcase/1)

    put_resp_header(conn, "vary", if("*" in values, do: "*", else: Enum.join(values, ", ")))
  end
end
