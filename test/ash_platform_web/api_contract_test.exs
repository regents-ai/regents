defmodule AshPlatformWeb.ApiContractTest do
  use AshPlatformWeb.ConnCase, async: true

  @contract Path.expand("../../contracts/api-contract.openapiv3.yaml", __DIR__)
  @served_contract Path.expand("../../priv/static/api-contract.openapiv3.yaml", __DIR__)

  test "the canonical contract declares the complete admitted browser auth surface" do
    contract = YamlElixir.read_from_file!(@contract)

    assert Map.keys(contract["paths"]) |> Enum.sort() == [
             "/api/techtree/v1/tree/nodes",
             "/auth/csrf",
             "/auth/privy/session",
             "/auth/session"
           ]

    assert Map.take(contract["paths"], ["/auth/csrf", "/auth/privy/session", "/auth/session"]) ==
             %{
               "/auth/csrf" => %{
                 "get" => %{
                   "operationId" => "getBrowserCsrf",
                   "responses" => %{
                     "200" => %{
                       "description" => "CSRF token for browser session changes",
                       "content" => %{
                         "application/json" => %{
                           "schema" => %{
                             "type" => "object",
                             "additionalProperties" => false,
                             "required" => ["csrf_token"],
                             "properties" => %{
                               "csrf_token" => %{"type" => "string", "minLength" => 1}
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               },
               "/auth/privy/session" => %{
                 "post" => %{
                   "operationId" => "createPrivyBrowserSession",
                   "security" => [%{"privyAccessToken" => [], "csrfToken" => []}],
                   "requestBody" => %{
                     "required" => false,
                     "content" => %{
                       "application/json" => %{
                         "schema" => %{
                           "type" => "object",
                           "maxProperties" => 0,
                           "additionalProperties" => false
                         }
                       }
                     }
                   },
                   "responses" => %{
                     "200" => %{"$ref" => "#/components/responses/Session"},
                     "401" => %{"$ref" => "#/components/responses/Unauthorized"},
                     "403" => %{"$ref" => "#/components/responses/CsrfForbidden"}
                   }
                 },
                 "delete" => %{
                   "operationId" => "deletePrivyBrowserSession",
                   "security" => [%{"csrfToken" => []}],
                   "responses" => %{
                     "200" => %{"$ref" => "#/components/responses/Logout"},
                     "403" => %{"$ref" => "#/components/responses/CsrfForbidden"}
                   }
                 }
               },
               "/auth/session" => %{
                 "get" => %{
                   "operationId" => "getBrowserSession",
                   "responses" => %{
                     "200" => %{"$ref" => "#/components/responses/Session"}
                   }
                 }
               }
             }

    assert contract["components"]["securitySchemes"] == %{
             "privyAccessToken" => %{
               "type" => "http",
               "scheme" => "bearer",
               "bearerFormat" => "Privy access token"
             },
             "cookieSession" => %{
               "type" => "apiKey",
               "in" => "cookie",
               "name" => "_ash_platform_key"
             },
             "csrfToken" => %{
               "type" => "apiKey",
               "in" => "header",
               "name" => "x-csrf-token"
             }
           }

    account_control = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["kind", "label", "profile_path", "avatar_data_uri"],
      "properties" => %{
        "kind" => %{"type" => "string", "enum" => ["sign_in", "signed_in"]},
        "label" => %{"type" => "string"},
        "profile_path" => %{"type" => ["string", "null"]},
        "avatar_data_uri" => %{
          "type" => ["string", "null"],
          "pattern" => "^data:image/svg\\+xml;base64,"
        }
      }
    }

    assert contract["components"]["schemas"]["Session"] == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => ["authenticated", "account_control"],
             "properties" => %{
               "authenticated" => %{"type" => "boolean"},
               "account_control" => account_control
             }
           }

    assert contract["components"]["schemas"]["Error"] == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => ["error"],
             "properties" => %{
               "error" => %{"type" => "string", "enum" => ["unauthorized"]}
             }
           }

    assert Map.take(contract["components"]["responses"], [
             "Session",
             "Unauthorized",
             "Logout",
             "CsrfForbidden"
           ]) == %{
             "Session" => %{
               "description" => "Current browser session",
               "content" => %{
                 "application/json" => %{
                   "schema" => %{"$ref" => "#/components/schemas/Session"}
                 }
               }
             },
             "Unauthorized" => %{
               "description" => "Privy access token was absent or invalid",
               "content" => %{
                 "application/json" => %{
                   "schema" => %{"$ref" => "#/components/schemas/Error"}
                 }
               }
             },
             "Logout" => %{
               "description" => "Local browser session removed",
               "content" => %{
                 "application/json" => %{
                   "schema" => %{
                     "type" => "object",
                     "additionalProperties" => false,
                     "required" => ["ok"],
                     "properties" => %{"ok" => %{"type" => "boolean", "const" => true}}
                   }
                 }
               }
             },
             "CsrfForbidden" => %{"description" => "CSRF token was absent or invalid"}
           }
  end

  test "the canonical contract declares the exact public node list" do
    contract = YamlElixir.read_from_file!(@contract)

    operation = contract["paths"]["/api/techtree/v1/tree/nodes"]["get"]
    assert operation["operationId"] == "listTreeNodes"
    assert operation["security"] == []
    assert operation["parameters"] == []
    assert operation["x-pagination"] == "none"

    response = operation["responses"]["200"]["content"]["application/json"]["schema"]
    assert response["additionalProperties"] == false
    assert response["required"] == ["data"]
    assert Map.keys(response["properties"]) == ["data"]

    node = contract["components"]["schemas"]["Node"]
    assert node["additionalProperties"] == false

    assert node["required"] == [
             "id",
             "tree_id",
             "title",
             "summary",
             "payload_hash",
             "published_at"
           ]

    assert Map.keys(node["properties"]) |> Enum.sort() ==
             ~w(id payload_hash published_at summary title tree_id)

    assert node["properties"]["id"] == %{"type" => "string", "format" => "uuid"}
    assert node["properties"]["tree_id"] == %{"type" => "string", "format" => "uuid"}
    assert node["properties"]["published_at"] == %{"type" => "string", "format" => "date-time"}
    assert node["properties"]["summary"]["type"] == ["string", "null"]
    assert node["properties"]["payload_hash"]["type"] == ["string", "null"]
  end

  test "the served contract is byte-identical and available over HTTP", %{conn: conn} do
    assert File.read!(@served_contract) == File.read!(@contract)

    conn = get(conn, "/api-contract.openapiv3.yaml")
    assert response(conn, 200) == File.read!(@contract)
    assert get_resp_header(conn, "content-type") == ["application/yaml"]
  end
end
