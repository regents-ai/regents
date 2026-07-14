defmodule AshPlatformWeb.NotebookStaticPlug do
  @moduledoc false
  use Plug.Builder

  @headers [
    {"access-control-allow-origin", "*"},
    {"cache-control", "public, max-age=31536000, immutable"},
    {"cross-origin-resource-policy", "cross-origin"},
    {"content-security-policy",
     "default-src 'none'; base-uri 'none'; object-src 'none'; form-action 'none'; frame-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob: https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' data: blob: https://cdn.jsdelivr.net https://wasm.marimo.app https://files.pythonhosted.org; worker-src 'self' blob:"}
  ]

  plug Plug.Static,
    at: "/",
    from: {:ash_platform, "priv/static/notebooks"},
    gzip: false,
    headers: @headers

  plug :not_found

  defp not_found(conn, _options), do: Plug.Conn.send_resp(conn, :not_found, "not found")
end
