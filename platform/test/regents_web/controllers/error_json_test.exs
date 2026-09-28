defmodule RegentsWeb.ErrorJSONTest do
  use RegentsWeb.ConnCase, async: true

  test "renders 404" do
    assert RegentsWeb.ErrorJSON.render("404.json", %{}) == %{
             error: %{code: "not_found", message: "Not Found", hint: hint()}
           }
  end

  test "renders 500" do
    assert RegentsWeb.ErrorJSON.render("500.json", %{}) == %{
             error: %{
               code: "internal_server_error",
               message: "Internal Server Error",
               hint: hint()
             }
           }
  end

  defp hint do
    base = RegentsWeb.Endpoint.url()
    "See #{base}/docs and #{base}/openapi.json for supported requests."
  end
end
