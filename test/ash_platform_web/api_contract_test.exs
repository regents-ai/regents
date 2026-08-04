defmodule AshPlatformWeb.ApiContractTest do
  use AshPlatformWeb.ConnCase, async: true

  alias AshPlatform.Techtree.PublicationInput

  @contract Path.expand("../../contracts/api-contract.openapiv3.yaml", __DIR__)
  @served_contract Path.expand("../../priv/static/api-contract.openapiv3.yaml", __DIR__)

  test "the canonical contract declares the complete admitted browser auth surface" do
    contract = YamlElixir.read_from_file!(@contract)

    assert Map.keys(contract["paths"]) |> Enum.sort() == [
             "/api/autolaunch/v1/auctions",
             "/api/autolaunch/v1/auctions/{id}",
             "/api/autolaunch/v1/auctions/{id}/bid-quote",
             "/api/autolaunch/v1/auctions/{id}/bids",
             "/api/autolaunch/v1/bids/{id}/claim",
             "/api/autolaunch/v1/bids/{id}/exit",
             "/api/autolaunch/v1/bids/{id}/return",
             "/api/autolaunch/v1/tokens",
             "/api/formation/v1/regents/{regent_id}/agent-links",
             "/api/formation/v1/regents/{regent_id}/agent-links/claim",
             "/api/techtree/v1/nodes",
             "/api/techtree/v1/nodes/{id}",
             "/api/techtree/v1/tree/nodes",
             "/api/techtree/v1/trees",
             "/api/techtree/v1/trees/{slug}/nodes",
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

  test "the agent pairing contract has one owner read and one SIWA-authenticated claim" do
    contract = YamlElixir.read_from_file!(@contract)
    paths = contract["paths"]

    index = paths["/api/formation/v1/regents/{regent_id}/agent-links"]["get"]
    assert index["operationId"] == "listRegentAgentLinks"
    assert index["security"] == [%{"cookieSession" => []}]
    assert index["parameters"] == [%{"$ref" => "#/components/parameters/RegentId"}]
    assert Map.keys(index["responses"]) |> Enum.sort() == ["200", "401", "404"]

    claim = paths["/api/formation/v1/regents/{regent_id}/agent-links/claim"]["post"]
    assert claim["operationId"] == "claimRegentAgentLink"
    assert claim["security"] == []

    assert Enum.map(claim["parameters"], & &1["$ref"]) == [
             "#/components/parameters/RegentId",
             "#/components/parameters/SiwaReceipt",
             "#/components/parameters/SiwaKeyId",
             "#/components/parameters/SiwaTimestamp",
             "#/components/parameters/SiwaAgentWallet",
             "#/components/parameters/SiwaAgentChainId",
             "#/components/parameters/SiwaAgentRegistry",
             "#/components/parameters/SiwaAgentTokenId",
             "#/components/parameters/HttpSignatureInput",
             "#/components/parameters/HttpSignature",
             "#/components/parameters/ContentDigest"
           ]

    assert claim["requestBody"] == %{
             "required" => true,
             "content" => %{
               "text/plain" => %{
                 "schema" => %{"type" => "string", "minLength" => 1, "maxLength" => 128}
               }
             }
           }

    assert Map.keys(claim["responses"]) |> Enum.sort() == ["201", "400", "401", "429"]

    assert claim["responses"]["429"] == %{
             "$ref" => "#/components/responses/AgentClaimRateLimited"
           }

    link = contract["components"]["schemas"]["AgentLink"]
    assert link["additionalProperties"] == false

    assert link["required"] == [
             "id",
             "regent_id",
             "agent_id",
             "registry_address",
             "token_id",
             "wallet",
             "paired_at"
           ]

    refute Map.has_key?(link["properties"], "human_account_id")
    refute Map.has_key?(link["properties"], "code")
    refute Map.has_key?(link["properties"], "signature")

    assert contract["components"]["schemas"]["AgentPairingError"]["properties"]["error"][
             "properties"
           ]["code"]["enum"] == [
             "not_found",
             "pairing_failed",
             "verification_failed",
             "rate_limited"
           ]
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

  test "the public Autolaunch contract is strict and additive" do
    contract = YamlElixir.read_from_file!(@contract)
    paths = contract["paths"]
    schemas = contract["components"]["schemas"]

    auctions = paths["/api/autolaunch/v1/auctions"]["get"]
    assert auctions["operationId"] == "listAuctions"
    assert auctions["security"] == []
    assert auctions["x-pagination"] == "none"

    assert auctions["parameters"] == [
             %{
               "name" => "mode",
               "in" => "query",
               "schema" => %{
                 "type" => "string",
                 "enum" => ["all", "biddable", "live", "failed_minimum", "graduated"],
                 "default" => "all"
               }
             },
             %{
               "name" => "sort",
               "in" => "query",
               "schema" => %{
                 "type" => "string",
                 "enum" => ["newest", "oldest"],
                 "default" => "newest"
               }
             },
             %{
               "name" => "limit",
               "in" => "query",
               "description" =>
                 "Values outside the admitted range are clamped to the nearest boundary.",
               "schema" => %{
                 "type" => "integer",
                 "minimum" => 1,
                 "maximum" => 50,
                 "default" => 50
               }
             }
           ]

    assert Map.keys(auctions["responses"]) |> Enum.sort() == ["200", "400", "500"]

    auction = paths["/api/autolaunch/v1/auctions/{id}"]["get"]
    assert auction["operationId"] == "getAuction"
    assert auction["security"] == []

    assert auction["parameters"] == [
             %{
               "name" => "id",
               "in" => "path",
               "required" => true,
               "schema" => %{"type" => "string", "format" => "uuid"}
             }
           ]

    assert Map.keys(auction["responses"]) |> Enum.sort() == ["200", "400", "404", "500"]

    tokens = paths["/api/autolaunch/v1/tokens"]["get"]
    assert tokens["operationId"] == "listTokens"
    assert tokens["security"] == []
    assert tokens["x-pagination"] == "none"

    assert tokens["parameters"] == [
             %{
               "name" => "limit",
               "in" => "query",
               "description" =>
                 "Values outside the admitted range are clamped to the nearest boundary.",
               "schema" => %{
                 "type" => "integer",
                 "minimum" => 1,
                 "maximum" => 100,
                 "default" => 100
               }
             }
           ]

    assert Map.keys(tokens["responses"]) |> Enum.sort() == ["200", "400", "500"]

    assert schemas["AuctionListEnvelope"] == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => ["data"],
             "properties" => %{
               "data" => %{
                 "type" => "array",
                 "items" => %{"$ref" => "#/components/schemas/Auction"}
               }
             }
           }

    assert schemas["AuctionEnvelope"] == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => ["data"],
             "properties" => %{
               "data" => %{"$ref" => "#/components/schemas/Auction"}
             }
           }

    assert schemas["Auction"]["additionalProperties"] == false
    assert schemas["Auction"]["required"] == ~w(id title summary featured state opened_at)

    assert Map.keys(schemas["Auction"]["properties"]) |> Enum.sort() ==
             ~w(featured id opened_at state summary title)

    assert schemas["TokenListEnvelope"] == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => ["data"],
             "properties" => %{
               "data" => %{
                 "type" => "array",
                 "items" => %{"$ref" => "#/components/schemas/Token"}
               }
             }
           }

    assert schemas["Token"]["additionalProperties"] == false

    assert schemas["Token"]["required"] ==
             ~w(id auction_id subject_id name symbol summary graduated_at top_rank)

    assert Map.keys(schemas["Token"]["properties"]) |> Enum.sort() ==
             ~w(auction_id graduated_at id name subject_id summary symbol top_rank)

    assert contract["components"]["schemas"]["ApiError"]["properties"]["error"]["properties"][
             "code"
           ]["enum"] == ["invalid_request", "internal_error"]

    assert schemas["NotFoundApiError"] == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => ["error"],
             "properties" => %{
               "error" => %{
                 "type" => "object",
                 "additionalProperties" => false,
                 "required" => ["code", "message"],
                 "properties" => %{
                   "code" => %{"type" => "string", "enum" => ["not_found"]},
                   "message" => %{"type" => "string"}
                 }
               }
             }
           }
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

      assert node_schema["properties"]["position"] == %{
               "$ref" => "#/components/schemas/NodePosition"
             }
    end

    refute "display_kind" in schemas["NodeListItem"]["required"]

    assert schemas["NodeListItem"]["properties"]["display_kind"] == %{
             "type" => "string",
             "default" => "standard"
           }
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
      "BaseMainnetProjectionReference"
    ]

    assert Enum.all?(planned_schema_names, &(schemas[&1]["additionalProperties"] == false))

    assert schemas["Tree"]["required"] == ["id", "slug", "name", "description"]
    refute Map.has_key?(schemas["Tree"]["properties"], "parent_id")

    node = schemas["Node"]

    assert node["required"] == [
             "id",
             "tree_id",
             "kind",
             "title",
             "summary",
             "payload_hash",
             "base_mainnet_projection",
             "edges",
             "published_at"
           ]

    assert node["properties"]["kind"]["type"] == ["string", "null"]
    refute Map.has_key?(node["properties"], "display_kind")

    for optional <-
          ~w(contributor_id lineage_node_ids capsule immutable_payloads evidence_projection evidence_state) do
      refute optional in node["required"]
      assert node["properties"][optional]["description"] =~ "Absent or null"
    end

    assert node["properties"]["lineage_node_ids"]["type"] == ["array", "null"]
    assert node["properties"]["immutable_payloads"]["type"] == ["array", "null"]

    for optional_ref <- ~w(capsule evidence_projection evidence_state) do
      assert %{"oneOf" => [ref, %{"type" => "null"}]} =
               node["properties"][optional_ref]

      assert Map.has_key?(ref, "$ref")
    end

    assert node["properties"]["base_mainnet_projection"] == %{
             "$ref" => "#/components/schemas/BaseMainnetProjectionReference"
           }

    assert node["properties"]["edges"] == %{
             "type" => "array",
             "description" =>
               "Typed curation edges touching this node, distinct from evidence lineage.",
             "items" => %{"$ref" => "#/components/schemas/Edge"}
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

    assert projection["properties"]["base_mainnet_projection"] == %{
             "$ref" => "#/components/schemas/BaseMainnetProjectionReference"
           }

    refute "base_mainnet_projection" in projection["required"]

    state = schemas["EvidenceState"]
    assert state["additionalProperties"] == false
    assert state["required"] == ["status", "updated_at"]
    assert "invalidated" in state["properties"]["status"]["enum"]
    assert "awaiting_revalidation" in state["properties"]["status"]["enum"]

    base_projection = schemas["BaseMainnetProjectionReference"]

    assert base_projection == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => [
               "chain_id",
               "projection_status",
               "record_uid",
               "transaction_hash",
               "block_number"
             ],
             "properties" => %{
               "chain_id" => %{"type" => "integer", "const" => 8453},
               "projection_status" => %{
                 "type" => "string",
                 "enum" => ["not_started", "pending", "submitted", "confirmed", "failed"]
               },
               "record_uid" => %{"type" => ["string", "null"], "minLength" => 1},
               "transaction_hash" => %{
                 "type" => ["string", "null"],
                 "pattern" => "^0x[0-9a-f]{64}$"
               },
               "block_number" => %{"type" => ["integer", "null"], "minimum" => 0}
             }
           }

    path_refs = collect_refs(contract["paths"])
    assert "#/components/schemas/TreeListEnvelope" in path_refs
    assert "#/components/schemas/TreeNodePageEnvelope" in path_refs
    assert "#/components/schemas/NodeEnvelope" in path_refs
  end

  test "the three Techtree reads declare bounded cursor pagination and five honest errors" do
    contract = YamlElixir.read_from_file!(@contract)
    paths = contract["paths"]
    parameters = contract["components"]["parameters"]
    schemas = contract["components"]["schemas"]

    assert paths["/api/techtree/v1/trees"]["get"]["operationId"] == "listTechtreeTrees"

    assert paths["/api/techtree/v1/trees"]["get"]["responses"]["200"]["description"] ==
             "Public Techtree trees; all research collections are public in this version"

    page = paths["/api/techtree/v1/trees/{slug}/nodes"]["get"]
    assert page["operationId"] == "listTechtreeTreeNodes"
    assert page["security"] == []

    assert page["parameters"] == [
             %{"$ref" => "#/components/parameters/TechtreeTreeSlug"},
             %{"$ref" => "#/components/parameters/TechtreeCursor"},
             %{"$ref" => "#/components/parameters/TechtreeLimit"}
           ]

    assert parameters["TechtreeLimit"]["schema"] == %{
             "type" => "integer",
             "minimum" => 1,
             "maximum" => 100,
             "default" => 25
           }

    assert parameters["TechtreeCursor"]["description"] =~
             "Tampering with a cursor voids the client's own pagination guarantees."

    assert schemas["TreeNodePageEnvelope"]["required"] == ["data", "edges", "next_cursor"]

    assert paths["/api/techtree/v1/nodes/{id}"]["get"]["operationId"] ==
             "getTechtreeNode"

    refute Map.has_key?(paths["/api/techtree/v1/nodes/{id}"]["get"]["responses"], "424")

    assert schemas["TechtreeReadError"]["properties"]["error"]["properties"]["code"][
             "enum"
           ] == [
             "not_found",
             "unauthorized",
             "temporarily_unavailable",
             "invalid_input",
             "artifact_unavailable"
           ]

    responses = contract["components"]["responses"]

    assert responses["TechtreeArtifactUnavailable"]["description"] =~
             "zs6.6 payload-access gate"

    assert Enum.all?(
             ~w(TechtreeInvalidInput TechtreeUnauthorized TechtreeNotFound TechtreeArtifactUnavailable TechtreeTemporarilyUnavailable),
             &(responses[&1]["content"]["application/json"]["schema"] == %{
                 "$ref" => "#/components/schemas/TechtreeReadError"
               })
           )
  end

  test "the Techtree publication contract is SIWA-authenticated, idempotent, and additive-open" do
    contract = YamlElixir.read_from_file!(@contract)
    operation = contract["paths"]["/api/techtree/v1/nodes"]["post"]
    schemas = contract["components"]["schemas"]

    assert operation["operationId"] == "publishTechtreeNode"
    assert operation["security"] == []

    assert Enum.map(operation["parameters"], & &1["$ref"]) == [
             "#/components/parameters/SiwaReceipt",
             "#/components/parameters/SiwaKeyId",
             "#/components/parameters/SiwaTimestamp",
             "#/components/parameters/SiwaAgentWallet",
             "#/components/parameters/SiwaAgentChainId",
             "#/components/parameters/SiwaAgentRegistry",
             "#/components/parameters/SiwaAgentTokenId",
             "#/components/parameters/HttpSignatureInput",
             "#/components/parameters/HttpSignature",
             "#/components/parameters/ContentDigest"
           ]

    assert operation["requestBody"] == %{
             "required" => true,
             "content" => %{
               "application/json" => %{
                 "schema" => %{"$ref" => "#/components/schemas/NodePublicationRequest"}
               }
             }
           }

    assert Map.keys(operation["responses"]) |> Enum.sort() ==
             ~w(200 201 400 401 403 409 503)

    request = schemas["NodePublicationRequest"]

    assert request["required"] ==
             ~w(regent_id tree_id kind title idempotency_key manifest_digest)

    assert request["discriminator"] == %{"propertyName" => "kind"}

    assert request["properties"]["kind"]["enum"] ==
             ~w(environment_family benchmark_slice uplift_report reproduction audit)

    assert request["properties"]["manifest_digest"]["pattern"] == "^[0-9a-f]{64}$"
    idempotency_key = request["properties"]["idempotency_key"]

    assert idempotency_key["pattern"] == PublicationInput.idempotency_key_pattern()

    assert idempotency_key["description"] ==
             "Leading and trailing Unicode White_Space code points are trimmed; at least one code point outside that exact class is required. U+FEFF is not blank."

    contract_pattern =
      idempotency_key["pattern"]
      |> String.replace(~r/\\u([0-9A-F]{4})/, "\\x{\\1}")
      |> Regex.compile!("u")

    for {value, accepted?} <- [{" ", false}, {<<0x85::utf8>>, false}, {<<0xFEFF::utf8>>, true}] do
      assert PublicationInput.nonblank?(value) == accepted?
      assert Regex.match?(contract_pattern, value) == accepted?
    end

    refute Map.has_key?(request, "additionalProperties")

    receipt = schemas["NodePublicationReceipt"]

    assert receipt["required"] == [
             "action_id",
             "capability_id",
             "action_kind",
             "resource_type",
             "resource_id",
             "status",
             "idempotency_key",
             "created_at",
             "updated_at",
             "public_url",
             "next_recommended_action",
             "next_poll_at",
             "approval_required",
             "error_code",
             "replayed"
           ]

    assert receipt["properties"]["capability_id"]["const"] == "techtree.node.publish"
    assert receipt["properties"]["status"]["enum"] == ["published", "failed"]
    assert receipt["properties"]["replayed"] == %{"type" => "boolean"}
    refute Map.has_key?(receipt, "additionalProperties")
    refute Map.has_key?(schemas["NodePublicationReceiptEnvelope"], "additionalProperties")
    refute Map.has_key?(schemas["NodePublicationErrorEnvelope"], "additionalProperties")

    error_codes =
      schemas["NodePublicationErrorEnvelope"]["properties"]["error"]["properties"]["code"][
        "enum"
      ]

    assert error_codes ==
             ~w(unauthorized forbidden conflict invalid_input temporarily_unavailable)
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
