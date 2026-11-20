defmodule RegentsWeb.HealthController do
  @moduledoc """
  Whether the site and its own database answer: `/healthz` in plain text for the
  host's health check, `/api/v1/health` in JSON for Sentinel and the command line.

  The JSON also says whether this release's migrations are all applied, and how
  each product answers (`Regents.Products.health/0`): `products` maps every
  product's name to `ok` or `unavailable`, and `status` is `ok` only when all are,
  else `degraded`. While the database answers the status code stays 200, whatever
  a product or the migrations say, so a fault in one product reads as that
  product and never as the site being down; only a database that does not answer
  is a 503.
  """
  use RegentsWeb, :controller

  alias Regents.{Health, Products}

  def show(conn, _params) do
    {status, body} =
      if Health.database_ready?(), do: {:ok, "ok"}, else: {:service_unavailable, "unavailable"}

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end

  def status(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    if Health.database_ready?() do
      products = Products.health()

      json(conn, %{
        status: if(Enum.all?(Map.values(products), &(&1 == "ok")), do: "ok", else: "degraded"),
        migrations_applied: Health.migrations_applied?(),
        products: products
      })
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{
        error: %{
          code: "unavailable",
          message: "The site is up but its database is not answering.",
          hint: "Try again in a minute."
        }
      })
    end
  end
end
