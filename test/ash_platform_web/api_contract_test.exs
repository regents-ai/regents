defmodule AshPlatformWeb.ApiContractTest do
  use ExUnit.Case, async: true

  @contract Path.expand("../../contracts/api-contract.openapiv3.yaml", __DIR__)
  @served_contract Path.expand("../../priv/static/api-contract.openapiv3.yaml", __DIR__)

  test "the narrow contract declares only the public node list" do
    contract = YamlElixir.read_from_file!(@contract)
    assert Map.keys(contract["paths"]) == ["/api/techtree/v1/tree/nodes"]
    operation = contract["paths"]["/api/techtree/v1/tree/nodes"]["get"]
    assert operation["operationId"] == "listTreeNodes"
    assert operation["security"] == []
    assert operation["parameters"] == []
    assert operation["x-pagination"] == "none"
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

  test "the router admits exactly one API operation" do
    api_routes =
      Enum.filter(AshPlatformWeb.Router.__routes__(), &String.starts_with?(&1.path, "/api/"))

    assert [{:get, "/api/techtree/v1/tree/nodes", AshPlatformWeb.TechtreeNodeController, :index}] =
             Enum.map(api_routes, &{&1.verb, &1.path, &1.plug, &1.plug_opts})
  end
end
