defmodule RegentsWeb.TelemetryTest do
  use ExUnit.Case, async: false

  import Plug.Test, only: [conn: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias Regents.Repo

  # Every site's dashboard reads request and query time by these names, so a
  # request and a query must each land in the scrape.
  test "a request is timed by its route pattern and a query by its whole time" do
    :get |> conn("/sitemap.xml") |> RegentsWeb.Endpoint.call(RegentsWeb.Endpoint.init([]))

    :ok = Sandbox.checkout(Repo)
    Repo.query!("SELECT 1")

    scrape = RegentsWeb.Telemetry.scrape()

    assert scrape =~
             ~r/^regents_request_duration_microseconds_count\{route="\/sitemap.xml"\} [1-9]/m

    assert scrape =~ ~r/^regents_repo_query_microseconds_count [1-9]/m
  end
end
