defmodule RegentAgentAccess.Plug do
  @moduledoc """
  Serves a product's explicitly public documents as Markdown at the same
  address as their HTML page, and chooses the format of error responses.

  Place it in the endpoint just before the router:

      plug RegentAgentAccess.Plug,
        documents: &MyAppWeb.PublicDocuments.document/1,
        guide: "/llms.txt"

  Options:

    * `:documents` - a function from a request path to `%{markdown: binary}` for
      a public document, or `nil` for every other address. The product owns this
      list. Only database-free, public content belongs in it; anything else
      falls through to the router with its real actors, policies and gates.
    * `:guide` - the path named in the refusal sent when a public document is
      asked for in a format it does not have.
    * `:json_prefixes` - first path segments whose errors are always JSON,
      whatever the `Accept` header says. Defaults to `["api"]`.

  Every response gains `Accept` in its `Vary` header. The plug never opens a
  route: an address that is not a public document passes through untouched,
  apart from the error format recorded for Phoenix's `render_errors`.
  """
  @behaviour Plug

  import Plug.Conn

  @document_formats [{"html", "text", "html"}, {"md", "text", "markdown"}]
  @error_formats @document_formats ++ [{"json", "application", "json"}]

  @impl Plug
  def init(opts) do
    %{
      documents: Keyword.fetch!(opts, :documents),
      guide: Keyword.fetch!(opts, :guide),
      json_prefixes: Keyword.get(opts, :json_prefixes, ["api"])
    }
  end

  @impl Plug
  def call(conn, %{documents: documents} = opts) do
    conn =
      conn
      |> register_before_send(&vary_accept/1)
      |> put_private(:phoenix_format, error_format(conn, opts))

    case conn.method in ["GET", "HEAD"] && documents.(conn.request_path) do
      %{markdown: markdown} -> public_document(conn, markdown, opts)
      _ -> conn
    end
  end

  defp error_format(%Plug.Conn{path_info: [prefix | _]} = conn, %{json_prefixes: prefixes}) do
    if prefix in prefixes, do: "json", else: negotiate(conn, @error_formats) || "html"
  end

  defp error_format(conn, _opts), do: negotiate(conn, @error_formats) || "html"

  defp public_document(conn, markdown, %{guide: guide}) do
    case negotiate(conn, @document_formats) do
      "md" ->
        conn
        |> Phoenix.Controller.put_secure_browser_headers()
        |> put_resp_content_type("text/markdown")
        |> send_resp(200, markdown)
        |> halt()

      "html" ->
        conn

      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          406,
          "This document is available as text/html or text/markdown. See #{guide}.\n"
        )
        |> halt()
    end
  end

  defp negotiate(conn, formats),
    do: conn |> get_req_header("accept") |> RegentAgentAccess.negotiate(formats)

  defp vary_accept(conn),
    do:
      put_resp_header(
        conn,
        "vary",
        conn |> get_resp_header("vary") |> RegentAgentAccess.merge_vary()
      )
end
