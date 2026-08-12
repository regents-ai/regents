defmodule AshPlatformWeb.HoldingControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  setup do
    Application.put_env(:ash_platform, :app_surfaces, false)
    on_exit(fn -> Application.put_env(:ash_platform, :app_surfaces, true) end)

    {:ok, document: build_conn() |> get("/app") |> html_response(503)}
  end

  test "[U5] the holding page says the area is not open yet and sends people home", %{
    document: document
  } do
    assert copy(document) =~ "Not open yet"
    assert copy(document) =~ "This part of Regent isn't open to visitors yet."
    assert copy(document) =~ "homepage"
  end

  test "[U5] the only control on the holding page goes to the marketing page", %{
    document: document
  } do
    page = LazyHTML.from_document(document)

    assert page |> LazyHTML.query("main a") |> LazyHTML.attribute("href") == ["/"]
    assert page |> LazyHTML.query("main button, main form, main input") |> Enum.count() == 0
  end

  test "[U2] the holding page is the site's own page, not a bare fragment", %{document: document} do
    assert document =~ "<!DOCTYPE html>"
    assert document =~ ~s(<meta name="csrf-token")

    assert document |> LazyHTML.from_document() |> LazyHTML.query("title") |> LazyHTML.text() =~
             "Not open yet"
  end

  defp copy(document) do
    document
    |> LazyHTML.from_document()
    |> LazyHTML.query("main")
    |> LazyHTML.text()
  end
end
