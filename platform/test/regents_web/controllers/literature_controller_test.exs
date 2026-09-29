defmodule RegentsWeb.LiteratureControllerTest do
  use RegentsWeb.ConnCase, async: true

  test "the chart places every book and shares its own picture" do
    document =
      build_conn() |> get("/literature") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query(".lit-book") |> Enum.count() ==
             length(RegentsWeb.Literature.books())

    assert document
           |> LazyHTML.query("meta[property='og:image']")
           |> LazyHTML.attribute("content") == [
             RegentsWeb.PublicDocuments.url("/images/literature/share.png")
           ]
  end
end
