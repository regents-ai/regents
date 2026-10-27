defmodule RegentsWeb.VisitLogPageTest do
  # Invariant: a page a browser opens through the endpoint belongs to a visit. The
  # first page starts one in the `_visit` cookie and names it for the page's own
  # scripts; a page opened with one keeps it.
  use RegentsWeb.ConnCase, async: true

  @visit ~r/\A[A-Za-z0-9_-]{22}\z/

  defp page(conn, path) do
    conn = conn |> put_req_header("accept", "text/html") |> get(path)

    named =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("meta[name=regent-visit]")
      |> LazyHTML.attribute("content")

    {conn, named}
  end

  test "the first page starts a visit and names it; the next page keeps it", %{conn: conn} do
    {first, named} = page(conn, "/")
    %{value: visit} = first.resp_cookies["_visit"]

    assert visit =~ @visit
    assert named == [visit]

    {next, named} = conn |> put_req_cookie("_visit", visit) |> page("/privacy")

    refute Map.has_key?(next.resp_cookies, "_visit")
    assert named == [visit]
  end
end
