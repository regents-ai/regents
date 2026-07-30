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

    assert response["properties"]["data"]["items"] == %{
             "$ref" => "#/components/schemas/NodeListItem"
           }

    node = contract["components"]["schemas"]["NodeListItem"]
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
             ~w(display_kind id payload_hash position published_at summary title tree_id)

    assert node["properties"]["id"] == %{"type" => "string", "format" => "uuid"}
    assert node["properties"]["tree_id"] == %{"type" => "string", "format" => "uuid"}
    assert node["properties"]["published_at"] == %{"type" => "string", "format" => "date-time"}
    assert node["properties"]["summary"]["type"] == ["string", "null"]
    assert node["properties"]["payload_hash"]["type"] == ["string", "null"]
  end

  test "the graph map contract extension is strict and additive" do
    contract = YamlElixir.read_from_file!(@contract)
    schemas = contract["components"]["schemas"]

    assert schemas["Tree"]["required"] == ["id", "slug", "name", "description"]
    refute "edges" in schemas["Tree"]["required"]

    assert schemas["Tree"]["properties"]["edges"] == %{
             "type" => "array",
             "description" =>
               "Curation and presentation relationships for the graph map, distinct from evidence lineage references.",
             "items" => %{"$ref" => "#/components/schemas/Edge"}
           }

    assert schemas["Edge"] == %{
             "type" => "object",
             "description" =>
               "A curation and presentation edge for the graph map, not an evidence lineage reference.",
             "additionalProperties" => false,
             "required" => ["from_node_id", "to_node_id", "kind"],
             "properties" => %{
               "from_node_id" => %{"type" => "string", "format" => "uuid"},
               "to_node_id" => %{"type" => "string", "format" => "uuid"},
               "kind" => %{
                 "type" => "string",
                 "enum" => ["prerequisite", "related"],
                 "default" => "prerequisite"
               }
             }
           }

    assert schemas["NodePosition"] == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => ["x", "y"],
             "properties" => %{
               "x" => %{"type" => "number", "format" => "float"},
               "y" => %{"type" => "number", "format" => "float"}
             }
           }

    for node_schema <- [schemas["NodeListItem"], schemas["Node"]] do
      refute "position" in node_schema["required"]
      refute "display_kind" in node_schema["required"]

      assert node_schema["properties"]["position"] == %{
               "$ref" => "#/components/schemas/NodePosition"
             }

      assert node_schema["properties"]["display_kind"] == %{
               "type" => "string",
               "default" => "standard"
             }
    end
  end

  test "the canonical contract declares strict planned Techtree components" do
    contract = YamlElixir.read_from_file!(@contract)
    schemas = contract["components"]["schemas"]

    planned_schema_names = [
      "Tree",
      "Node",
      "Capsule",
      "ImmutablePayload",
      "EvidenceProjection",
      "EvidenceState",
      "BaseMainnetRecordReference"
    ]

    assert Enum.all?(planned_schema_names, &(schemas[&1]["additionalProperties"] == false))

    assert schemas["Tree"]["required"] == ["id", "slug", "name", "description"]
    refute Map.has_key?(schemas["Tree"]["properties"], "parent_id")

    node = schemas["Node"]

    assert node["properties"]["kind"]["enum"] == [
             "environment_family",
             "benchmark_slice",
             "uplift_report",
             "reproduction",
             "audit"
           ]

    assert node["properties"]["base_mainnet_record"] == %{
             "$ref" => "#/components/schemas/BaseMainnetRecordReference"
           }

    capsule = schemas["Capsule"]

    assert capsule["required"] == [
             "declared_digest",
             "resolved_digest",
             "observed_digest",
             "material_difference_summary"
           ]

    assert Map.keys(capsule["properties"]) |> Enum.sort() ==
             ~w(declared_digest material_difference_summary observed_digest resolved_digest)

    for digest <- ~w(declared_digest resolved_digest observed_digest) do
      assert capsule["properties"][digest] == %{
               "type" => "string",
               "pattern" => "^[0-9a-f]{64}$"
             }
    end

    payload = schemas["ImmutablePayload"]
    assert payload["required"] == ~w(schema_version media_type sha256 visibility)
    assert payload["properties"]["sha256"]["pattern"] == "^[0-9a-f]{64}$"
    assert payload["properties"]["visibility"]["enum"] == ["public", "commitment"]
    refute "content_uri" in payload["required"]

    projection = schemas["EvidenceProjection"]

    assert projection["properties"]["outcome"] == %{
             "type" => "string",
             "enum" => ["positive", "null", "negative", "inconclusive", "invalid"]
           }

    assurance = projection["properties"]["assurance_dimensions"]
    assert assurance["additionalProperties"] == false

    assert assurance["required"] == [
             "artifact_integrity",
             "execution_evidence",
             "verifier_quality",
             "experimental_strength",
             "generalization_strength",
             "independent_reproduction",
             "production_support",
             "freshness"
           ]

    for commitment <-
          ~w(receipt_commitment claim_commitment report_commitment decision_commitment) do
      assert projection["properties"][commitment] == %{
               "$ref" => "#/components/schemas/ImmutablePayload"
             }
    end

    assert projection["properties"]["base_mainnet_record"] == %{
             "$ref" => "#/components/schemas/BaseMainnetRecordReference"
           }

    refute "base_mainnet_record" in projection["required"]

    state = schemas["EvidenceState"]
    assert state["additionalProperties"] == false
    assert state["required"] == ["status", "updated_at"]
    assert "invalidated" in state["properties"]["status"]["enum"]
    assert "awaiting_revalidation" in state["properties"]["status"]["enum"]

    base_record = schemas["BaseMainnetRecordReference"]
    assert base_record["properties"]["chain_id"] == %{"type" => "integer", "const" => 8453}
    assert base_record["additionalProperties"] == false
    refute Map.has_key?(base_record["properties"], "action")

    path_refs = collect_refs(contract["paths"])

    refute Enum.any?(
             path_refs,
             &(&1 in Enum.map(planned_schema_names, fn name -> "#/components/schemas/#{name}" end))
           )
  end

  test "the served contract is byte-identical and available over HTTP", %{conn: conn} do
    assert File.read!(@served_contract) == File.read!(@contract)

    conn = get(conn, "/api-contract.openapiv3.yaml")
    assert response(conn, 200) == File.read!(@contract)
    assert get_resp_header(conn, "content-type") == ["application/yaml"]
  end

  defp collect_refs(%{"$ref" => ref}), do: [ref]

  defp collect_refs(value) when is_map(value) do
    value
    |> Map.values()
    |> Enum.flat_map(&collect_refs/1)
  end

  defp collect_refs(value) when is_list(value), do: Enum.flat_map(value, &collect_refs/1)
  defp collect_refs(_value), do: []
end
