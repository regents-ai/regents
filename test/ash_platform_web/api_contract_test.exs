defmodule AshPlatformWeb.ApiContractTest do
  use ExUnit.Case, async: true

  @contract Path.expand("../../contracts/api-contract.openapiv3.yaml", __DIR__)
  @served_contract Path.expand("../../priv/static/api-contract.openapiv3.yaml", __DIR__)

  test "the canonical contract declares the public node list and browser auth surface" do
    contract = YamlElixir.read_from_file!(@contract)

    assert Map.keys(contract["paths"]) |> Enum.sort() == [
             "/api/techtree/v1/tree/nodes",
             "/auth/csrf",
             "/auth/privy/session",
             "/auth/session"
           ]

    operation = contract["paths"]["/api/techtree/v1/tree/nodes"]["get"]
    assert operation["operationId"] == "listTreeNodes"
    assert operation["security"] == []
    assert operation["parameters"] == []
    assert operation["x-pagination"] == "none"

    assert contract["paths"]["/auth/csrf"]["get"]["operationId"] == "getBrowserCsrf"

    create_session = contract["paths"]["/auth/privy/session"]["post"]
    assert create_session["operationId"] == "createPrivyBrowserSession"
    assert create_session["security"] == [%{"privyAccessToken" => [], "csrfToken" => []}]

    delete_session = contract["paths"]["/auth/privy/session"]["delete"]
    assert delete_session["operationId"] == "deletePrivyBrowserSession"
    assert delete_session["security"] == [%{"csrfToken" => []}]

    assert contract["paths"]["/auth/session"]["get"]["operationId"] ==
             "getBrowserSession"

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
  end

  test "the served contract is byte-identical" do
    assert File.read!(@served_contract) == File.read!(@contract)
  end

  test "the router admits exactly the contracted HTTP operations" do
    http_routes =
      Enum.filter(AshPlatformWeb.Router.__routes__(), fn route ->
        String.starts_with?(route.path, "/api/") or String.starts_with?(route.path, "/auth/")
      end)

    assert Enum.map(http_routes, &{&1.verb, &1.path, &1.plug, &1.plug_opts}) == [
             {:get, "/api/techtree/v1/tree/nodes", AshPlatformWeb.TechtreeNodeController, :index},
             {:get, "/auth/csrf", AshPlatformWeb.PrivySessionController, :csrf},
             {:post, "/auth/privy/session", AshPlatformWeb.PrivySessionController, :create},
             {:get, "/auth/session", AshPlatformWeb.PrivySessionController, :show},
             {:delete, "/auth/privy/session", AshPlatformWeb.PrivySessionController, :delete}
           ]
  end
end
