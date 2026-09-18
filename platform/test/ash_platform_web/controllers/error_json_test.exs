defmodule AshPlatformWeb.ErrorJSONTest do
  use AshPlatformWeb.ConnCase, async: true

  test "renders 404" do
    assert AshPlatformWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found", code: "not_found", hint: hint()}
           }
  end

  test "renders 500" do
    assert AshPlatformWeb.ErrorJSON.render("500.json", %{}) == %{
             errors: %{
               detail: "Internal Server Error",
               code: "internal_server_error",
               hint: hint()
             }
           }
  end

  defp hint do
    base = AshPlatformWeb.Endpoint.url()
    "See #{base}/docs and #{base}/openapi.json for supported requests."
  end
end
