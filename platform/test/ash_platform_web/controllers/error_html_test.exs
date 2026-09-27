defmodule AshPlatformWeb.ErrorHTMLTest do
  use AshPlatformWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "ERROR_HEADLINES: a missing page says so in plain words" do
    assert render_to_string(AshPlatformWeb.ErrorHTML, "404", "html", []) =~
             "We can’t find that page</h1>"
  end

  test "ERROR_HEADLINES: any other failure says something went wrong" do
    assert render_to_string(AshPlatformWeb.ErrorHTML, "500", "html", []) =~
             "Something went wrong</h1>"
  end
end
