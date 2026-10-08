defmodule RegentsWeb.PublicReadErrorsTest do
  use RegentsWeb.ConnCase, async: false

  # Every refusal from the product and stake reads says what happened and what
  # to do next.
  test "an unknown product names the ones that exist", %{conn: conn} do
    assert conn |> get("/api/v1/products/nope") |> json_response(404) == %{
             "error" => %{
               "code" => "product_not_found",
               "message" => "There is no product with that name.",
               "hint" => "Use one of: autolaunch, techtree, patchbay, keyfleet."
             }
           }
  end

  test "the product reads take no query", %{conn: conn} do
    expected = %{
      "error" => %{
        "code" => "invalid_query",
        "message" => "This read takes no query parameters.",
        "hint" => "Send the request again without a query string."
      }
    }

    assert conn |> get("/api/v1/products?x=1") |> json_response(400) == expected

    assert conn |> recycle() |> get("/api/v1/products/techtree?x=1") |> json_response(400) ==
             expected
  end

  test "the stake read asks for a sign-in" do
    previous = Application.get_env(:regents, :privy)
    Application.put_env(:regents, :privy, app_id: "stake-fixture", verification_key: "unused")
    on_exit(fn -> Application.put_env(:regents, :privy, previous || []) end)

    assert build_conn() |> get("/api/v1/staking/position") |> json_response(401) == %{
             "error" => %{
               "code" => "authentication_required",
               "message" => "Sign in to read your stake.",
               "hint" =>
                 "Send the Privy access token as a Bearer token and the identity token in privy-id-token, both from the same sign-in."
             }
           }
  end
end
