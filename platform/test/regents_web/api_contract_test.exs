defmodule RegentsWeb.ApiContractTest do
  use RegentsWeb.ConnCase, async: true

  @contract Path.expand("../../contracts/api-contract.openapiv3.yaml", __DIR__)
  @served_contract Application.app_dir(:regents, "priv/static/api-contract.openapiv3.yaml")

  test "the canonical contract declares the complete admitted browser auth surface" do
    contract = YamlElixir.read_from_file!(@contract)

    assert Map.keys(contract["paths"]) |> Enum.sort() == [
             "/api/agents/v1/me",
             "/api/agents/v1/pair",
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

  test "agents pair and check in with SIWA-signed requests" do
    contract = YamlElixir.read_from_file!(@contract)
    paths = contract["paths"]

    signed_headers = [
      "#/components/parameters/SiwaReceipt",
      "#/components/parameters/SiwaKeyId",
      "#/components/parameters/SiwaTimestamp",
      "#/components/parameters/SiwaAgentWallet",
      "#/components/parameters/SiwaAgentChainId",
      "#/components/parameters/HttpSignatureInput",
      "#/components/parameters/HttpSignature"
    ]

    pair = paths["/api/agents/v1/pair"]["post"]
    assert pair["operationId"] == "pairAgent"
    assert pair["security"] == []

    assert Enum.map(pair["parameters"], & &1["$ref"]) ==
             signed_headers ++ ["#/components/parameters/ContentDigest"]

    assert pair["requestBody"]["content"]["application/json"]["schema"]["required"] ==
             ["code", "name", "harness"]

    assert Map.keys(pair["responses"]) |> Enum.sort() == ["201", "400", "401", "429"]

    me = paths["/api/agents/v1/me"]["get"]
    assert me["operationId"] == "checkInAgent"
    assert me["security"] == []
    assert Enum.map(me["parameters"], & &1["$ref"]) == signed_headers
    assert Map.keys(me["responses"]) |> Enum.sort() == ["200", "401", "404", "429"]

    budget_headers = %{
      "RateLimit" => %{"$ref" => "#/components/headers/RateLimit"},
      "RateLimit-Policy" => %{"$ref" => "#/components/headers/RateLimitPolicy"}
    }

    assert pair["responses"]["201"]["headers"] == budget_headers
    assert me["responses"]["200"]["headers"] == budget_headers

    assert contract["components"]["responses"]["AgentRateLimited"]["headers"] ==
             Map.put(budget_headers, "Retry-After", %{"$ref" => "#/components/headers/RetryAfter"})

    assert contract["components"]["schemas"]["AgentHarness"]["enum"] ==
             Enum.map(Regents.Agents.Harness.values(), &Atom.to_string/1)

    assert contract["components"]["schemas"]["PairedAgent"]["required"] ==
             ["name", "harness", "wallet", "paired_at", "last_contact_at"]

    # A check-in also names the account the agent is paired with.
    assert me["responses"]["200"]["content"]["application/json"]["schema"] ==
             %{"$ref" => "#/components/schemas/CheckedInAgentEnvelope"}

    assert contract["components"]["schemas"]["CheckedInAgent"]["required"] ==
             ["name", "harness", "wallet", "paired_at", "last_contact_at", "account"]

    assert contract["components"]["schemas"]["PairedAccount"]["required"] ==
             ["display_name", "ens_name"]
  end

  test "the public API description publishes the agent operations exactly as the contract states them",
       %{conn: conn} do
    contract = YamlElixir.read_from_file!(@contract)
    public = conn |> get("/openapi.json") |> json_response(200)
    agent_paths = ["/api/agents/v1/me", "/api/agents/v1/pair"]

    assert Map.take(public["paths"], agent_paths) == Map.take(contract["paths"], agent_paths)

    for ref <- refs(Map.take(contract["paths"], agent_paths), contract) do
      ["#", "components", section, name] = String.split(ref, "/")
      assert public["components"][section][name] == contract["components"][section][name]
    end
  end

  test "the served contract is byte-identical and available over HTTP", %{conn: conn} do
    assert File.read!(@served_contract) == File.read!(@contract)

    conn = get(conn, "/api-contract.openapiv3.yaml")
    assert response(conn, 200) == File.read!(@contract)
    assert get_resp_header(conn, "content-type") == ["application/yaml"]
  end

  # Every component the given part of a document points at, followed through
  # the components themselves.
  defp refs(part, contract) do
    part
    |> direct_refs()
    |> Enum.flat_map(fn ref ->
      ["#", "components", section, name] = String.split(ref, "/")
      [ref | refs(contract["components"][section][name], contract)]
    end)
    |> Enum.uniq()
  end

  defp direct_refs(%{"$ref" => ref}), do: [ref]
  defp direct_refs(%{} = map), do: map |> Map.values() |> Enum.flat_map(&direct_refs/1)
  defp direct_refs(list) when is_list(list), do: Enum.flat_map(list, &direct_refs/1)
  defp direct_refs(_value), do: []
end
