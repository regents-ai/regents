defmodule AshPlatformWeb.ApiContractTest do
  use AshPlatformWeb.ConnCase, async: true

  @contract Path.expand("../../contracts/api-contract.openapiv3.yaml", __DIR__)
  @served_contract Application.app_dir(:ash_platform, "priv/static/api-contract.openapiv3.yaml")

  test "the canonical contract declares the complete admitted browser auth surface" do
    contract = YamlElixir.read_from_file!(@contract)

    assert Map.keys(contract["paths"]) |> Enum.sort() == [
             "/api/autolaunch/v1/auctions",
             "/api/autolaunch/v1/auctions/{id}",
             "/api/autolaunch/v1/auctions/{id}/bid-quote",
             "/api/autolaunch/v1/tokens",
             "/api/autolaunch/v1/treasury-security/{address}",
             "/api/formation/v1/regents/{regent_id}/agent-links",
             "/api/formation/v1/regents/{regent_id}/agent-links/claim",
             "/auth/csrf",
             "/auth/privy/failure",
             "/auth/privy/session",
             "/auth/session"
           ]

    assert Map.take(contract["paths"], [
             "/auth/csrf",
             "/auth/privy/failure",
             "/auth/privy/session",
             "/auth/session"
           ]) ==
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
                     },
                     "429" => %{
                       "description" =>
                         "Too many new browser sessions were started from the client address",
                       "headers" => %{
                         "Retry-After" => %{
                           "schema" => %{"type" => "string", "const" => "300"}
                         },
                         "Cache-Control" => %{
                           "schema" => %{"type" => "string", "const" => "no-store"}
                         }
                       },
                       "content" => %{
                         "application/json" => %{
                           "schema" => %{
                             "type" => "object",
                             "additionalProperties" => false,
                             "required" => ["error"],
                             "properties" => %{
                               "error" => %{"type" => "string", "const" => "rate_limited"}
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               },
               "/auth/privy/failure" => %{
                 "post" => %{
                   "operationId" => "reportPrivyBrowserFailure",
                   "security" => [%{"csrfToken" => []}],
                   "requestBody" => %{
                     "required" => true,
                     "content" => %{
                       "application/json" => %{
                         "schema" => %{
                           "type" => "object",
                           "additionalProperties" => false,
                           "required" => ["reason"],
                           "properties" => %{
                             "reason" => %{
                               "type" => "string",
                               "enum" => [
                                 "bridge_startup",
                                 "flow_closed",
                                 "invalid_message",
                                 "provider_error",
                                 "request_timeout",
                                 "session_exchange",
                                 "unable_to_sign"
                               ]
                             }
                           }
                         }
                       }
                     }
                   },
                   "responses" => %{
                     "204" => %{"description" => "Diagnostic accepted or safely ignored"},
                     "403" => %{"$ref" => "#/components/responses/CsrfForbidden"}
                   }
                 }
               },
               "/auth/privy/session" => %{
                 "post" => %{
                   "operationId" => "createPrivyBrowserSession",
                   "security" => [
                     %{
                       "privyAccessToken" => [],
                       "privyIdentityToken" => [],
                       "csrfToken" => []
                     }
                   ],
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
                     "401" => %{"$ref" => "#/components/responses/PrivySessionUnauthorized"},
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
             "privyIdentityToken" => %{
               "type" => "apiKey",
               "in" => "header",
               "name" => "privy-id-token"
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
      "required" => ["kind", "label", "profile_path", "avatar_src"],
      "properties" => %{
        "kind" => %{"type" => "string", "enum" => ["sign_in", "signed_in"]},
        "label" => %{"type" => "string"},
        "profile_path" => %{"type" => ["string", "null"]},
        "avatar_src" => %{
          "type" => ["string", "null"],
          "pattern" => "^(https://|data:image/svg\\+xml;base64,)"
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
             "PrivySessionUnauthorized",
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
               "description" =>
                 "The Privy access and identity tokens were not both present and valid for one signed-in session",
               "content" => %{
                 "application/json" => %{
                   "schema" => %{"$ref" => "#/components/schemas/Error"}
                 }
               }
             },
             # Only the browser sign-in exchange may publish the marker, and only
             # as an optional header on a body identical to every other refusal.
             "PrivySessionUnauthorized" => %{
               "description" =>
                 "The Privy access and identity tokens were not both present and valid for one signed-in session",
               "headers" => %{
                 "x-ash-provider-relogin" => %{
                   "description" =>
                     "Present only when the access token itself could not be verified, which permits one fresh provider login",
                   "required" => false,
                   "schema" => %{"type" => "string", "const" => "allowed"}
                 }
               },
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

    assert schemas["Auction"]["required"] ==
             ~w(id title summary featured state opened_at treasury_security)

    assert Map.keys(schemas["Auction"]["properties"]) |> Enum.sort() ==
             ~w(featured id opened_at state summary title treasury_security)

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
             ~w(id auction_id subject_id name symbol summary graduated_at top_rank treasury_security)

    assert Map.keys(schemas["Token"]["properties"]) |> Enum.sort() ==
             ~w(auction_id graduated_at id name subject_id summary symbol top_rank treasury_security)

    assert contract["components"]["schemas"]["ApiError"]["properties"]["error"]["properties"][
             "code"
           ]["enum"] == ["invalid_request", "internal_error"]

    # The superseded protected bidder-preparation operations and every component
    # only they referenced are gone; the public quote is all that remains.
    for orphaned <- ~w(PreparedAuctionWalletAction ExactTokenApproval) do
      refute Map.has_key?(schemas, orphaned)
    end

    refute Map.has_key?(contract["components"]["responses"], "PreparedWalletAction")
    refute Map.has_key?(contract["components"]["parameters"], "BidId")

    for action <- ~w(submit_bid exit_bid return_quote_token claim_bid) do
      refute File.read!(@contract) =~ action
    end

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

  test "the served contract is byte-identical and available over HTTP", %{conn: conn} do
    assert File.read!(@served_contract) == File.read!(@contract)

    conn = get(conn, "/api-contract.openapiv3.yaml")
    assert response(conn, 200) == File.read!(@contract)
    assert get_resp_header(conn, "content-type") == ["application/yaml"]
  end
end
