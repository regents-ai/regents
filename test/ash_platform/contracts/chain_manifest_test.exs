defmodule AshPlatform.Contracts.ChainManifestTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @manifest_path Path.join(@root, "contracts/base-mainnet.json")
  @staking_abi_sha256 "c8c5570f76f32b72e3bdb0a062fc97cb7f74aacadf03683d796b57a765f1ca23"
  @redeemer_abi_sha256 "c14a490d3feefbee76fd08e5f993d987e27388cb6c78f4643e2d8010c34766fd"
  @auction_abi_sha256 "901e5873cc24b52eac61553bcdee68c208fb4c210e081337fdbad28f5ac61b76"
  @erc20_approve_abi_sha256 "c3b0ea0f4cb03cf09bee2ef0ea451c976bcfb13c658f5f6d37784699d567efec"
  @payment_link_abi_sha256 "121d3ae7e3e260ade1fda995b4ba67cae9b1bf11814497d2cedd788dfb839343"
  @payment_link_created_signature "PaymentLinkCreated(bytes32,address,address,string,bool)"
  @payment_link_created_topic0 "0x06c00f03aef858d7f694c6f34c8245765bedf95c92e4341eec90f78b7d24bedb"
  @ingress_abi_sha256 "5175b02535ed6058b2abcc27215680316d634ec77c06359ae3aa9b2174366da6"
  @splitter_abi_sha256 "a21b53836c452ce8bb6c3892543cb47521ff9186a01e3327363cc5853f9da69e"

  setup_all do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()
    {:ok, manifest: manifest}
  end

  test "pins Base mainnet and the permanent staking deployment", %{manifest: manifest} do
    assert manifest["chain"] == %{
             "id" => 8453,
             "name" => "Base",
             "environment" => "mainnet"
           }

    staking = manifest["contracts"]["regent_revenue_staking"]

    assert staking["address"] == "0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5"

    assert staking["deployment_transaction"] ==
             "0xf30488de7242c2fa35ef419227ef296472a993e7c17311adf24ccdc8d73ab5dd"

    assert staking["runtime_code"] == %{
             "bytes" => 11_757,
             "sha256" => "9e7d05378e4aeddb4db00bdaa88e6a466c3061d6514a760bbe93fa5d665129bb",
             "keccak256" => "0xcaef93094fa27d35f5ff9e619d5ee75528c7c18f19f4f31a0a5eaba62a976497"
           }

    assert staking["onchain_constants"] == %{
             "stake_token" => "0x6f89bcA4eA5931EdFCB09786267b251DeE752b07",
             "usdc" => "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
           }

    assert staking["verified_source"] == %{
             "status" => "exact_match",
             "contract_name" => "RegentRevenueStaking",
             "url" =>
               "https://basescan.org/address/0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5#code"
           }

    assert staking["reads"] == [
             %{"id" => "stake_token", "signature" => "stakeToken()", "selector" => "0x51ed6a30"},
             %{"id" => "usdc", "signature" => "usdc()", "selector" => "0x3e413bee"},
             %{"id" => "paused", "signature" => "paused()", "selector" => "0x5c975abb"},
             %{
               "id" => "total_staked",
               "signature" => "totalStaked()",
               "selector" => "0x817b1cd2"
             },
             %{
               "id" => "staked_balance",
               "signature" => "stakedBalance(address)",
               "selector" => "0x60217267"
             },
             %{
               "id" => "claimable_usdc",
               "signature" => "previewClaimableUSDC(address)",
               "selector" => "0xb026ee79"
             },
             %{
               "id" => "claimable_regent",
               "signature" => "previewClaimableRegent(address)",
               "selector" => "0xf653a7f7"
             },
             %{
               "id" => "funded_claimable_regent",
               "signature" => "previewFundedClaimableRegent(address)",
               "selector" => "0xb4010d49"
             }
           ]

    assert_selectors(staking["reads"])
    assert_abi_contains(manifest, "regent_revenue_staking", staking["reads"])
  end

  test "pins every founder staking action and derives each selector", %{manifest: manifest} do
    actions = manifest["contracts"]["regent_revenue_staking"]["prepared_actions"]

    assert Enum.map(actions, & &1["id"]) == [
             "stake",
             "unstake",
             "claim_usdc",
             "claim_regent",
             "claim_and_restake_regent"
           ]

    assert Enum.map(actions, & &1["signature"]) == [
             "stake(uint256,address)",
             "unstake(uint256,address)",
             "claimUSDC(address)",
             "claimRegent(address)",
             "claimAndRestakeRegent()"
           ]

    assert Enum.map(actions, &Map.take(&1, ["value", "signer_class", "beneficiary_class"])) == [
             %{
               "value" => "0",
               "signer_class" => "staker_wallet",
               "beneficiary_class" => "staking_contract"
             },
             %{
               "value" => "0",
               "signer_class" => "staker_wallet",
               "beneficiary_class" => "staker_wallet"
             },
             %{
               "value" => "0",
               "signer_class" => "staker_wallet",
               "beneficiary_class" => "staker_wallet"
             },
             %{
               "value" => "0",
               "signer_class" => "staker_wallet",
               "beneficiary_class" => "staker_wallet"
             },
             %{
               "value" => "0",
               "signer_class" => "staker_wallet",
               "beneficiary_class" => "staker_wallet"
             }
           ]

    assert hd(actions)["argument_bindings"] == %{
             "amount" => "requested_stake_amount",
             "receiver" => "connected_wallet"
           }

    assert hd(actions)["approval"] == %{
             "token" => "stake_token",
             "spender" => "regent_revenue_staking",
             "amount" => "requested_stake_amount",
             "mode" => "exact"
           }

    assert Enum.at(actions, 1)["argument_bindings"]["recipient"] == "connected_wallet"
    assert Enum.at(actions, 2)["argument_bindings"] == %{"recipient" => "connected_wallet"}
    assert Enum.at(actions, 3)["argument_bindings"] == %{"recipient" => "connected_wallet"}
    assert List.last(actions)["argument_bindings"] == %{}
    assert_selectors(actions)
    assert_abi_contains(manifest, "regent_revenue_staking", actions)
  end

  test "pins the redemption contracts, economics, and exact approval rule", %{manifest: manifest} do
    contracts = manifest["contracts"]
    redeemer = contracts["animata_redeemer"]

    assert redeemer["address"] == "0x71065b775a590c43933f10c0055dc7d74afabb0e"

    assert redeemer["deployment_transaction"] ==
             "0x0bada3b11435990bfe2efe7758afc08510d0c7676b19b78439d8c389186ccd35"

    assert redeemer["runtime_code"]["bytes"] == 8_613

    assert redeemer["runtime_code"]["keccak256"] ==
             "0xb2a6b47cb6b6bf34c7b0d0e47fb24c14c8ea2dbdf502325aa120042355e46eb7"

    assert redeemer["onchain_constants"] == %{
             "animata_i" => "0x78402119Ec6349A0D41F12b54938De7BF783C923",
             "animata_ii" => "0x903C4c1E8B8532FbD3575482d942D493eb9266e2",
             "result_collection" => "0x2208aaDBdEcd47D3B4430b5b75a175f6d885D487",
             "usdc" => "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
             "regent" => "0x6f89bcA4eA5931EdFCB09786267b251DeE752b07",
             "usdc_price_atomic" => "80000000",
             "max_source_token_id" => 999,
             "regent_payout_atomic" => "5000000000000000000000000",
             "vest_duration_seconds" => 604_800
           }

    assert manifest["redemption_policy"] == %{
             "eligible_collections" => ["animata_i", "animata_ii"],
             "usdc_approval_spender" => "animata_redeemer",
             "usdc_approval_amount_atomic" => "80000000",
             "usdc_approval_mode" => "exact",
             "result_collection_is_not_redeemable_input" => true
           }

    assert contracts["animata_i"]["address"] == redeemer["onchain_constants"]["animata_i"]
    assert contracts["animata_ii"]["address"] == redeemer["onchain_constants"]["animata_ii"]
    assert contracts["base_usdc"]["address"] == redeemer["onchain_constants"]["usdc"]

    assert contracts["animata_i"]["runtime_code"] == %{
             "bytes" => 19_658,
             "sha256" => "d3b5023b1875fa83f99571621bfeeaebceaaf095655b41392fc89a3df816a0ba",
             "keccak256" => "0x69e7a7158f30acb817dc83a4e21af19a216c3a2ae57db423599ca82f321e3041"
           }

    assert contracts["animata_ii"]["runtime_code"] == contracts["animata_i"]["runtime_code"]

    assert redeemer["verified_source"] == %{
             "status" => "exact_match",
             "contract_name" => "AnimataRedeemer",
             "url" =>
               "https://basescan.org/address/0x71065b775a590c43933f10c0055dc7d74afabb0e#code"
           }
  end

  test "derives every redemption and standard token selector", %{manifest: manifest} do
    redeemer = manifest["contracts"]["animata_redeemer"]
    rows = redeemer["prepared_actions"] ++ redeemer["reads"]

    assert Enum.map(rows, & &1["id"]) == [
             "approve_nft_collection",
             "approve_exact_usdc",
             "redeem",
             "claim",
             "claimable",
             "vest",
             "animata_i",
             "animata_ii",
             "result_collection",
             "usdc",
             "usdc_price",
             "price",
             "regent",
             "regent_payout",
             "vest_duration",
             "max_source_token_id",
             "result_token_id"
           ]

    assert Enum.map(rows, & &1["signature"]) == [
             "setApprovalForAll(address,bool)",
             "approve(address,uint256)",
             "redeem(address,uint256)",
             "claim()",
             "claimable(address)",
             "getVest(address)",
             "COLL1()",
             "COLL2()",
             "COLL3()",
             "USDC()",
             "USDC_PRICE()",
             "price()",
             "REGENT()",
             "REGENT_PAYOUT()",
             "VEST_DURATION()",
             "MAX_ID()",
             "mapToCollection3(address,uint256)"
           ]

    assert Enum.map(
             redeemer["prepared_actions"],
             &Map.take(&1, ["id", "target", "value", "signer_class", "beneficiary_class", "risk"])
           ) == [
             %{
               "id" => "approve_nft_collection",
               "target" => "selected_eligible_collection",
               "value" => "0",
               "signer_class" => "redeemer_wallet",
               "beneficiary_class" => "animata_redeemer",
               "risk" => "collection_wide_operator_approval"
             },
             %{
               "id" => "approve_exact_usdc",
               "target" => "base_usdc",
               "value" => "0",
               "signer_class" => "redeemer_wallet",
               "beneficiary_class" => "animata_redeemer",
               "risk" => "exact_token_allowance"
             },
             %{
               "id" => "redeem",
               "target" => "animata_redeemer",
               "value" => "0",
               "signer_class" => "redeemer_wallet",
               "beneficiary_class" => "connected_wallet"
             },
             %{
               "id" => "claim",
               "target" => "animata_redeemer",
               "value" => "0",
               "signer_class" => "redeemer_wallet",
               "beneficiary_class" => "connected_wallet"
             }
           ]

    [approve_nft, approve_usdc | _] = redeemer["prepared_actions"]

    assert approve_nft["argument_bindings"] == %{
             "operator" => "animata_redeemer",
             "approved" => true
           }

    assert approve_usdc["argument_bindings"] == %{
             "spender" => "animata_redeemer",
             "amount_atomic" => "80000000",
             "mode" => "exact"
           }

    assert_selectors(rows)
    assert_abi_contains(manifest, "animata_redeemer", Enum.drop(rows, 2))

    standard = manifest["standard_interfaces"]

    assert Enum.map(standard["erc20"], & &1["id"]) == [
             "approve",
             "balance_of",
             "allowance",
             "decimals"
           ]

    assert Enum.map(standard["erc721"], & &1["id"]) == [
             "owner_of",
             "is_approved_for_all",
             "set_approval_for_all"
           ]

    standard |> Map.values() |> List.flatten() |> assert_selectors()
  end

  test "canonicalizes nested tuple ABI inputs before deriving runtime selectors" do
    abi =
      @root
      |> Path.join("contracts/abi/animata-redeemer.json")
      |> File.read!()
      |> Jason.decode!()

    permit = Enum.find(abi, &(&1["name"] == "redeemWithPermit"))

    signature =
      Mix.Tasks.AshPlatform.VerifyChainManifest.canonical_signature(permit)

    assert signature ==
             "redeemWithPermit(address,uint256,((address,uint256),uint256,uint256),bytes)"

    cast = System.find_executable("cast") || flunk("Foundry cast is required for chain checks")
    {selector, 0} = System.cmd(cast, ["sig", signature], stderr_to_stdout: true)
    assert String.trim(selector) == "0x37b2dab2"
  end

  test "verified ABI files are canonical and complete", %{manifest: manifest} do
    for id <- ["regent_revenue_staking", "animata_redeemer"] do
      contract = manifest["contracts"][id]
      abi_path = Path.join([@root, "contracts", contract["abi"]["path"]])
      bytes = File.read!(abi_path)
      digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      abi = Jason.decode!(bytes)

      expected_digest =
        if id == "regent_revenue_staking", do: @staking_abi_sha256, else: @redeemer_abi_sha256

      assert contract["abi"]["canonical_sha256"] == expected_digest
      assert digest == expected_digest
      assert Enum.count(abi, &(&1["type"] == "function")) == contract["abi"]["function_count"]
      assert is_list(abi)
    end
  end

  test "chain admission pins auction bid actions and exact quote-token approval" do
    admission =
      @root
      |> Path.join("contracts/chain-contracts.yaml")
      |> YamlElixir.read_from_file!()
      |> get_in(["contracts"])
      |> List.first()

    assert admission["admitted_prepared_actions"] == [
             "continuous_clearing_auction.submit_bid",
             "continuous_clearing_auction.exit_bid",
             "continuous_clearing_auction.return_quote_token",
             "continuous_clearing_auction.claim_bid",
             "quote_token_erc20.approve_exact"
           ]

    evidence = Map.new(admission["reviewed_action_evidence"], &{&1["contract_id"], &1})
    auction = evidence["continuous_clearing_auction"]
    erc20 = evidence["quote_token_erc20"]
    payment_links = evidence["payment_link_factory"]
    ingress = evidence["revenue_ingress_account"]
    subject_erc20 = evidence["subject_token_erc20"]
    splitter = evidence["revenue_share_splitter_v2"]

    assert auction["contract_name"] == "IContinuousClearingAuction"
    assert auction["target"] == "stored_auction_address"

    assert auction["interface_note"] ==
             "submit_bid uses the upstream four-argument convenience overload of the canonical five-argument submitBid and defaults prevTickPriceQ96 to FLOOR_PRICE_Q96; see Uniswap/continuous-clearing-auction src/ContinuousClearingAuction.sol lines 635-641."

    assert auction["action_ids"] == ~w(submit_bid exit_bid return_quote_token claim_bid)
    assert erc20["target"] == "stored_quote_token_address"
    assert erc20["action_ids"] == ["approve_exact"]
    refute Map.has_key?(evidence, "regent_staking_revenue_router")
    assert payment_links["target"] == "stored_subject_factory_address"
    assert payment_links["implementation_provenance"] =~ "PaymentLinkFactory.sol:30-36,64-115,197"
    assert payment_links["confirmation_event_signature"] == @payment_link_created_signature
    assert payment_links["confirmation_event_topic0"] == @payment_link_created_topic0
    assert keccak(@payment_link_created_signature) == @payment_link_created_topic0
    assert ingress["target"] == "stored_subject_ingress_account"
    assert ingress["implementation_provenance"] =~ "RevenueIngressAccount.sol:183-206"
    assert subject_erc20["target"] == "stored_subject_token_address"
    assert subject_erc20["implementation_provenance"] =~ "RevenueShareSplitterV2.sol:45"
    assert subject_erc20["implementation_provenance"] =~ "RevenueShareSplitterV2.sol:174"
    assert subject_erc20["implementation_provenance"] =~ "RevenueShareSplitterV2.sol:299-310"
    assert subject_erc20["implementation_provenance"] =~ "RevenueShareSplitterV2.sol:781"
    assert splitter["target"] == "stored_subject_splitter_address"
    assert splitter["implementation_provenance"] =~ "RevenueShareSplitterV2.sol:299-328"
    assert splitter["implementation_provenance"] =~ "RevenueShareSplitterV2.sol:432-442"

    for {entry, digest} <- [
          {auction, @auction_abi_sha256},
          {erc20, @erc20_approve_abi_sha256},
          {payment_links, @payment_link_abi_sha256},
          {ingress, @ingress_abi_sha256},
          {subject_erc20, @erc20_approve_abi_sha256},
          {splitter, @splitter_abi_sha256}
        ] do
      path = Path.join([@root, "contracts", entry["abi_path"]])
      assert File.regular?(path)
      assert entry["abi_sha256"] == digest
      assert Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) == digest
    end

    assert_selectors([
      %{"signature" => "submitBid(uint256,uint128,address,bytes)", "selector" => "0x140fe8ee"},
      %{"signature" => "exitBid(uint256)", "selector" => "0x8e4deb17"},
      %{"signature" => "claimTokens(uint256)", "selector" => "0x46e04a2f"},
      %{"signature" => "approve(address,uint256)", "selector" => "0x095ea7b3"}
    ])
  end

  test "S3 ABI mutability and returns match the vendored revenue implementations" do
    root = Path.join(@root, "contracts/abi")

    payment_links =
      root
      |> Path.join("payment-link-factory.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.new(&{&1["name"], &1})

    assert payment_links["createPaymentLink"]["stateMutability"] == "nonpayable"
    assert Enum.map(payment_links["createPaymentLink"]["outputs"], & &1["type"]) == ["address"]
    assert payment_links["createCanonicalPaymentLink"]["stateMutability"] == "nonpayable"

    for name <- ["setPaymentLinkCanonical", "setPaymentLinkReceiverState"] do
      assert payment_links[name]["stateMutability"] == "nonpayable"
      assert payment_links[name]["outputs"] == []
    end

    event = payment_links["PaymentLinkCreated"]
    assert event["anonymous"] == false

    assert Enum.map(event["inputs"], &{&1["type"], &1["indexed"]}) == [
             {"bytes32", true},
             {"address", true},
             {"address", true},
             {"string", false},
             {"bool", false}
           ]

    [sweep] =
      root
      |> Path.join("revenue-ingress-account.json")
      |> File.read!()
      |> Jason.decode!()

    assert sweep["stateMutability"] == "nonpayable"
    assert Enum.map(sweep["outputs"], & &1["type"]) == ["uint256", "uint256"]

    splitter =
      root
      |> Path.join("revenue-share-splitter-v2.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.new(&{&1["name"], &1})

    for name <- ["stake", "unstake"] do
      assert splitter[name]["stateMutability"] == "nonpayable"
      assert splitter[name]["outputs"] == []
    end

    assert splitter["claimUSDC"]["stateMutability"] == "nonpayable"
    assert Enum.map(splitter["claimUSDC"]["outputs"], & &1["type"]) == ["uint256"]
  end

  defp assert_abi_contains(manifest, contract_id, rows) do
    abi_path = manifest["contracts"][contract_id]["abi"]["path"]

    signatures =
      @root
      |> Path.join("contracts")
      |> Path.join(abi_path)
      |> File.read!()
      |> Jason.decode!()
      |> Enum.filter(&(&1["type"] == "function"))
      |> Enum.map(fn item ->
        types = item["inputs"] |> Enum.map_join(",", & &1["type"])
        "#{item["name"]}(#{types})"
      end)
      |> MapSet.new()

    assert Enum.all?(rows, &MapSet.member?(signatures, &1["signature"]))
  end

  defp assert_selectors(rows) do
    cast = System.find_executable("cast") || flunk("Foundry cast is required for chain checks")

    for row <- rows do
      {selector, 0} = System.cmd(cast, ["sig", row["signature"]], stderr_to_stdout: true)
      assert String.trim(selector) == row["selector"]
    end
  end

  defp keccak(signature) do
    cast = System.find_executable("cast") || flunk("Foundry cast is required for chain checks")
    {topic, 0} = System.cmd(cast, ["keccak", signature], stderr_to_stdout: true)
    String.trim(topic)
  end
end
