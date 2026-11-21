defmodule RegentsWeb.Plugs.ReadOnly do
  @moduledoc """
  Where the site only reads (`Regents.read_only?/0`), refuses every request that
  would sign in, pair, check in, save, or read as a signed-in person or a paired
  agent, with one plain answer: 403 `read_only`. Elsewhere it lets the request
  through.

  The router puts it before the sign-in addresses, agents' own requests
  (`/api/agents/v1`), every paired agent's request, and the signed-in reads and
  the profile API, so none of them asks the sign-in service or reads an account.
  """

  @behaviour Plug

  import Plug.Conn

  @body Jason.encode!(%{
          error: %{
            code: "read_only",
            message: "This copy of Regent only shows its pages.",
            hint: "Sign in, pair an agent and check in at https://regents.sh."
          }
        })

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: if(Regents.read_only?(), do: refuse(conn), else: conn)

  defp refuse(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(:forbidden, @body)
    |> halt()
  end
end
