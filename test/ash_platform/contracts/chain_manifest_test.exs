defmodule AshPlatform.Contracts.ChainManifestTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)
  @manifest_path Path.join(@root, "contracts/base-mainnet.json")
  @staking_abi_sha256 "c8c5570f76f32b72e3bdb0a062fc97cb7f74aacadf03683d796b57a765f1ca23"
  @redeemer_abi_sha256 "c14a490d3feefbee76fd08e5f993d987e27388cb6c78f4643e2d8010c34766fd"
  @auction_abi_sha256 "f687d42ad0fd981e38ba7f43baad6428014f5056a129a7bf13906f5704e5194b"
  @permit2_abi_sha256 "ced6a1b558e80e4a80c5bc1920da8cca21fa63806ac379b5c1c8ab4b6c866832"
  @bid_submitted_signature "BidSubmitted(uint256,address,uint256,uint128)"
  @bid_submitted_topic0 "0x650baad5cd8ca09b8f580be220fa04ce2ba905a041f764b6a3fe2c848eb70540"
  @erc20_approve_abi_sha256 "c3b0ea0f4cb03cf09bee2ef0ea451c976bcfb13c658f5f6d37784699d567efec"
  @subject_splitter_abi_sha256 "d51e10161f411ecb2ea85254aa982f4edd40e53f227a859f771d76f8d554467a"
  @payment_receiver_abi_sha256 "626c528c84686d6b1840e6df969029a07728e3165fed14779ff9dadd8bbe1469"
  @factory_abi_sha256 "38bd540d5bdc286ab0eb6e5eaff819b17a0ee54ebdc8e9d9d98bfb8745d398a7"
  @strategy_abi_sha256 "d149ece5a73cdb35a33e1ff0e1c136d1a5ffc776df272c6e569b05894ffbcf04"
  @c5_source_commit "b87c9e7a7c9f5d6b9df19ca44c33666ca67d273f"
  @c5_source_tree "ac6c9f82b57320726dcefa68c5ebaca76858bf2d"
  @c5_abi_surface_sha256 "71f2fa413751de63d6d7bae16cebdf9fcec54d0e79d081058ac704404c0c65c3"
  @c5_release_manifest_sha256 "629220ba90579bd3cbd1616ef7c1de5ca67f9b982e2f453b3aaad1e3159b675a"
  @c5_fork_observations_sha256 "198a4ab782db2bcec4b02e2594ad3c96133867e56a5ccbea6570d224c4597b7c"

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

  test "chain admission admits the staking actions alone while the bidder interface stays evidence" do
    admission =
      @root
      |> Path.join("contracts/chain-contracts.yaml")
      |> YamlElixir.read_from_file!()
      |> get_in(["contracts"])
      |> List.first()

    assert admission["authority"] == "evidence_only"

    assert admission["autolaunch_consumer_freeze"] == %{
             "repository" => "autolaunch-contracts",
             "source_commit" => @c5_source_commit,
             "source_tree" => @c5_source_tree,
             "abi_surface_sha256" => @c5_abi_surface_sha256,
             "release_manifest_sha256" => @c5_release_manifest_sha256,
             "fork_observations_sha256" => @c5_fork_observations_sha256,
             "deployment_status" => "deployment_pending",
             "admission" => "disabled"
           }

    assert admission["admitted_prepared_actions"] == [
             "regent_revenue_staking.stake",
             "regent_revenue_staking.unstake",
             "regent_revenue_staking.claim_usdc",
             "regent_revenue_staking.claim_regent",
             "regent_revenue_staking.claim_and_restake_regent"
           ]

    evidence = Map.new(admission["reviewed_action_evidence"], &{&1["contract_id"], &1})

    # Every other reviewed contract, including every Autolaunch one, is absent.
    for {contract_id, entry} <- evidence,
        contract_id != "regent_revenue_staking",
        action_id <- entry["action_ids"] do
      refute "#{contract_id}.#{action_id}" in admission["admitted_prepared_actions"]
    end

    auction = evidence["continuous_clearing_auction"]
    permit2 = evidence["permit2"]
    erc20 = evidence["quote_token_erc20"]
    subject_erc20 = evidence["subject_token_erc20"]
    splitter = evidence["subject_splitter_v1"]
    receiver = evidence["payment_receiver_v1"]

    assert auction["contract_name"] == "IContinuousClearingAuction"
    assert auction["target"] == "stored_auction_address"
    assert auction["source_commit"] == "7d7602d257733315434570f2a0c2f94f1c7b207a"
    assert auction["action_ids"] == ["submit_bid"]
    assert auction["confirmation_event_signature"] == @bid_submitted_signature
    assert auction["confirmation_event_topic0"] == @bid_submitted_topic0
    assert keccak(@bid_submitted_signature) == @bid_submitted_topic0

    # The obsolete four-argument overload and every position action are gone.
    assert auction["interface_note"] =~ "canonical five-argument submitBid"
    assert auction["interface_note"] =~ "src/ContinuousClearingAuction.sol lines 464-482"
    assert auction["interface_note"] =~ "Permit2 at line 479"

    assert permit2["contract_name"] == "IAllowanceTransfer"
    assert permit2["address"] == "0x000000000022D473030F116dDEE9F6B43aC78BA3"
    assert permit2["source_commit"] == "cc56ad0f3439c502c246fc5cfcc3db92bb8b7219"
    assert permit2["address_provenance"] =~ "Solady"
    assert permit2["address_provenance"] =~ "2af06408b6a204824c2ecb245779ed400b535fb5"
    assert permit2["address_provenance"] =~ "src/utils/SafeTransferLib.sol line 64"
    assert permit2["action_ids"] == ["approve"]

    assert erc20["target"] == "stored_quote_token_address"
    assert erc20["action_ids"] == ["approve_exact"]
    assert erc20["interface_note"] =~ "canonical Permit2 spender"
    refute Map.has_key?(evidence, "regent_staking_revenue_router")

    # Every superseded archived-Platform revenue contract is gone.
    for contract_id <- [
          "payment_link_factory",
          "revenue_ingress_account",
          "revenue_share_splitter_v2"
        ] do
      refute Map.has_key?(evidence, contract_id)
    end

    assert subject_erc20["target"] == "stored_subject_token_address"
    assert subject_erc20["implementation_provenance"] =~ @c5_source_commit
    assert subject_erc20["implementation_provenance"] =~ "SubjectSplitterV1.sol:62"
    assert subject_erc20["implementation_provenance"] =~ "exact splitter spender"

    assert splitter["contract_name"] == "SubjectSplitterV1"
    assert splitter["target"] == "stored_subject_splitter_address"
    assert splitter["action_ids"] == ["stake", "unstake", "claim", "claim_all"]
    assert splitter["implementation_provenance"] =~ "SubjectSplitterV1.sol"
    assert splitter["implementation_provenance"] =~ "lines 192-232"
    assert splitter["interface_note"] =~ "no recipient-argument overload and no"
    assert splitter["interface_note"] =~ "truthful no-op"

    assert receiver["contract_name"] == "PaymentReceiverV1"
    assert receiver["target"] == "projected_canonical_receiver_address"
    assert receiver["action_ids"] == ["pay", "sweep", "set_receiver_note"]
    assert receiver["implementation_provenance"] =~ "PaymentReceiverV1.sol"
    assert receiver["interface_note"] =~ "referralBps() is 0"
    assert receiver["interface_note"] =~ "projected canonical_receiver_address"

    # Both entries pin the exact integrated contract source and tree.
    for entry <- [splitter, receiver] do
      assert entry["source_commit"] == @c5_source_commit
      assert entry["source_tree"] == @c5_source_tree
    end

    # Every declared confirmation event topic is an independent Keccak-256.
    for entry <- [splitter, receiver],
        signature <- entry["confirmation_event_signatures"] do
      assert keccak(signature) ==
               AshPlatform.WalletActions.SubjectAbi.selector(event_id(signature))
    end

    for {entry, digest} <- [
          {auction, @auction_abi_sha256},
          {permit2, @permit2_abi_sha256},
          {erc20, @erc20_approve_abi_sha256},
          {subject_erc20, @erc20_approve_abi_sha256},
          {splitter, @subject_splitter_abi_sha256},
          {receiver, @payment_receiver_abi_sha256}
        ] do
      path = Path.join([@root, "contracts", entry["abi_path"]])
      assert File.regular?(path)
      assert entry["abi_sha256"] == digest
      assert Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) == digest
    end

    assert_selectors(
      auction["reads"] ++
        permit2["reads"] ++
        [
          %{
            "signature" => "submitBid(uint256,uint128,address,uint256,bytes)",
            "selector" => "0xa52c8728"
          },
          %{"signature" => "approve(address,address,uint160,uint48)", "selector" => "0x87517c45"},
          %{"signature" => "approve(address,uint256)", "selector" => "0x095ea7b3"}
        ]
    )
  end

  # The bidder ABI is derived from exact pinned source, so the shapes the
  # confirmation path decodes are proved against the file rather than assumed.
  test "the pinned auction ABI declares only the canonical bid interface" do
    abi =
      @root
      |> Path.join("contracts/abi/continuous-clearing-auction.json")
      |> File.read!()
      |> Jason.decode!()

    assert Enum.map(abi, &{&1["type"], &1["name"]}) == [
             {"function", "submitBid"},
             {"function", "currency"},
             {"event", "BidSubmitted"}
           ]

    [submit_bid, currency, event] = abi

    assert submit_bid["stateMutability"] == "payable"

    assert Enum.map(submit_bid["inputs"], &{&1["name"], &1["type"]}) == [
             {"maxPriceQ96", "uint256"},
             {"amount", "uint128"},
             {"owner", "address"},
             {"prevTickPriceQ96", "uint256"},
             {"hookData", "bytes"}
           ]

    assert submit_bid["notice"] =~ "src/interfaces/IContinuousClearingAuction.sol:136-142"
    assert submit_bid["notice"] =~ "collects a non-native currency only through Permit2"

    assert currency["stateMutability"] == "view"
    assert currency["inputs"] == []
    assert Enum.map(currency["outputs"], & &1["type"]) == ["address"]

    assert event["anonymous"] == false

    assert Enum.map(event["inputs"], &{&1["name"], &1["type"], &1["indexed"]}) == [
             {"id", "uint256", true},
             {"owner", "address", true},
             {"priceQ96", "uint256", false},
             {"amount", "uint128", false}
           ]
  end

  test "the pinned Permit2 ABI declares the exact allowance interface the auction needs" do
    abi =
      @root
      |> Path.join("contracts/abi/permit2.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.new(&{&1["name"], &1})

    assert Enum.map(abi["approve"]["inputs"], &{&1["name"], &1["type"]}) == [
             {"token", "address"},
             {"spender", "address"},
             {"amount", "uint160"},
             {"expiration", "uint48"}
           ]

    assert abi["approve"]["stateMutability"] == "nonpayable"
    assert abi["approve"]["outputs"] == []

    assert Enum.map(abi["allowance"]["inputs"], &{&1["name"], &1["type"]}) == [
             {"user", "address"},
             {"token", "address"},
             {"spender", "address"}
           ]

    assert Enum.map(abi["allowance"]["outputs"], &{&1["name"], &1["type"]}) == [
             {"amount", "uint160"},
             {"expiration", "uint48"},
             {"nonce", "uint48"}
           ]

    # A zero expiration lasts only the current block, so the encoder refuses one.
    assert_raise FunctionClauseError, fn ->
      AshPlatform.WalletActions.Permit2Abi.encode_approve(
        "0x1111111111111111111111111111111111111111",
        "0x2222222222222222222222222222222222222222",
        1,
        0
      )
    end
  end

  # The final C5 ABI is derived from exact pinned source, so the shapes this lane
  # encodes and decodes are proved against the file rather than assumed.
  test "the final C5 splitter ABI declares exactly the caller-only customer surface" do
    abi = consumer_abi("subject-splitter-v1.json")

    assert Enum.map(abi, &{&1["type"], &1["name"]}) == [
             {"function", "stake"},
             {"function", "unstake"},
             {"function", "claim"},
             {"function", "claimAll"},
             {"function", "subject"},
             {"function", "usdc"},
             {"function", "regent"},
             {"function", "treasury"},
             {"function", "totalStaked"},
             {"function", "stakedOf"},
             {"function", "claimable"},
             {"event", "Staked"},
             {"event", "Unstaked"},
             {"event", "Claimed"}
           ]

    by_name = Map.new(abi, &{&1["name"], &1})

    # Every customer call takes its caller's own position and nothing else.
    for name <- ["stake", "unstake"] do
      assert by_name[name]["stateMutability"] == "nonpayable"
      assert Enum.map(by_name[name]["inputs"], & &1["type"]) == ["uint256"]
      assert by_name[name]["outputs"] == []
    end

    assert Enum.map(by_name["claim"]["inputs"], & &1["type"]) == ["address"]
    assert by_name["claimAll"]["inputs"] == []

    assert Enum.map(by_name["claimable"]["inputs"], & &1["type"]) == ["address", "address"]
    assert by_name["claimable"]["stateMutability"] == "view"

    assert Enum.map(by_name["Claimed"]["inputs"], &{&1["name"], &1["type"], &1["indexed"]}) == [
             {"account", "address", true},
             {"token", "address", true},
             {"amount", "uint256", false}
           ]

    for name <- ["Staked", "Unstaked"] do
      assert by_name[name]["anonymous"] == false

      assert Enum.map(by_name[name]["inputs"], &{&1["type"], &1["indexed"]}) == [
               {"address", true},
               {"uint256", false}
             ]
    end

    for entry <- abi, do: assert(entry["notice"] =~ @c5_source_commit)

    encoded = Jason.encode!(abi)
    refute encoded =~ "RecoveryAdminHasNoCode"
    refute encoded =~ "4f986444"
  end

  test "the final C5 receiver ABI declares exactly the payment surface and its two events" do
    abi = consumer_abi("payment-receiver-v1.json")

    assert Enum.map(abi, &{&1["type"], &1["name"]}) ==
             [
               {"function", "pay"},
               {"function", "sweep"},
               {"function", "setReceiverNote"},
               {"function", "splitter"},
               {"function", "beneficiary"},
               {"function", "referralBps"},
               {"function", "noteEditor"},
               {"function", "receiverNote"},
               {"function", "subject"},
               {"function", "usdc"},
               {"function", "regent"},
               {"function", "treasury"}
             ] ++ [{"event", "PaymentRouted"}, {"event", "ReceiverNoteUpdated"}]

    by_name = Map.new(abi, &{&1["name"], &1})

    assert Enum.map(by_name["pay"]["inputs"], & &1["type"]) == ["address", "uint256", "bytes32"]
    assert Enum.map(by_name["sweep"]["inputs"], & &1["type"]) == ["address", "bytes32"]
    assert Enum.map(by_name["setReceiverNote"]["inputs"], & &1["type"]) == ["bytes32"]
    assert by_name["referralBps"]["stateMutability"] == "view"
    assert Enum.map(by_name["referralBps"]["outputs"], & &1["type"]) == ["uint16"]

    # The route event carries the actual gross, referral and net in its data, so a
    # sweep learns the amount it really moved.
    assert Enum.map(by_name["PaymentRouted"]["inputs"], &{&1["name"], &1["type"], &1["indexed"]}) ==
             [
               {"paymentRef", "bytes32", true},
               {"receiverNote", "bytes32", true},
               {"token", "address", true},
               {"gross", "uint256", false},
               {"referral", "uint256", false},
               {"net", "uint256", false}
             ]

    # Neither note field is indexed, so both ride in the data words.
    assert Enum.map(
             by_name["ReceiverNoteUpdated"]["inputs"],
             &{&1["name"], &1["type"], &1["indexed"]}
           ) == [{"previousNote", "bytes32", false}, {"newNote", "bytes32", false}]

    for entry <- abi, do: assert(entry["notice"] =~ @c5_source_commit)
  end

  # The final C5 ABI is derived from exact pinned source, so the shapes this lane
  # encodes and decodes are proved against the file rather than assumed.
  test "the final C5 factory ABI declares exactly the one customer call and its review reads" do
    abi = consumer_abi("regents-autolaunch-factory-v1.json")

    assert Enum.map(abi, &{&1["type"], &1["name"]}) == [
             {"function", "launch"},
             {"function", "launchFee"},
             {"function", "launchesPaused"},
             {"function", "strategy"},
             {"function", "launches"},
             {"function", "launchIdOfSubject"},
             {"event", "LaunchCreated"},
             {"event", "LaunchFeeCollected"}
           ]

    by_name = Map.new(abi, &{&1["name"], &1})

    # The launcher supplies one tuple and nothing else: no start block, floor
    # price, hook, pool setting, salt, supply, allocation or schedule.
    assert [%{"type" => "tuple", "components" => components}] = by_name["launch"]["inputs"]
    assert by_name["launch"]["stateMutability"] == "nonpayable"

    assert Enum.map(components, &{&1["name"], &1["type"]}) == [
             {"name", "string"},
             {"symbol", "string"},
             {"description", "string"},
             {"website", "string"},
             {"image", "string"},
             {"treasury", "address"},
             {"recoveryAdmin", "address"},
             {"requiredRegentRaised", "uint128"},
             {"expectedLaunchFee", "uint256"}
           ]

    # Reads are reads and the approval is a mutation; nothing here blurs them.
    for name <- ["launchFee", "launchesPaused", "strategy", "launches", "launchIdOfSubject"] do
      assert by_name[name]["stateMutability"] == "view"
    end

    assert [%{"type" => "tuple", "components" => record}] = by_name["launches"]["outputs"]
    assert Enum.map(record, & &1["type"]) == List.duplicate("address", 6)

    assert Enum.map(
             by_name["LaunchCreated"]["inputs"],
             &{&1["name"], &1["type"], &1["indexed"]}
           ) == [
             {"launchId", "uint256", true},
             {"launcher", "address", true},
             {"subject", "address", true},
             {"auction", "address", false},
             {"escrow", "address", false},
             {"treasury", "address", false},
             {"recoveryAdmin", "address", false},
             {"requiredRegentRaised", "uint128", false},
             {"startBlock", "uint64", false},
             {"endBlock", "uint64", false}
           ]

    assert Enum.map(
             by_name["LaunchFeeCollected"]["inputs"],
             &{&1["name"], &1["type"], &1["indexed"]}
           ) == [
             {"launchId", "uint256", true},
             {"payer", "address", true},
             {"regentSafe", "address", false},
             {"amount", "uint256", false}
           ]

    for entry <- abi, do: assert(entry["notice"] =~ @c5_source_commit)
  end

  test "the final C5 strategy ABI declares only the reciprocal binding and the frozen terms" do
    abi = consumer_abi("regent-lbp-strategy-v1.json")

    assert Enum.map(abi, & &1["name"]) == [
             "factory",
             "START_DELAY_BLOCKS",
             "AUCTION_DURATION_BLOCKS",
             "CLAIM_DELAY_BLOCKS",
             "MIGRATION_DELAY_BLOCKS",
             "FLOOR_PRICE_Q96",
             "BID_TICK_Q96",
             "AUCTION_ALLOCATION",
             "RESERVE_ALLOCATION",
             "PENDING_ALLOCATION",
             "POOL_FEE",
             "POOL_TICK_SPACING",
             "MAX_REACHABLE_RAISE"
           ]

    by_name = Map.new(abi, &{&1["name"], &1})

    # Every term is a read with no argument, so none of them can be chosen.
    for entry <- abi do
      assert entry["type"] == "function"
      assert entry["stateMutability"] == "view"
      assert entry["inputs"] == []
      assert entry["notice"] =~ @c5_source_commit
    end

    # The one signed term, and the one whose word therefore needs bringing back.
    assert Enum.map(by_name["POOL_TICK_SPACING"]["outputs"], & &1["type"]) == ["int24"]
    assert by_name["POOL_TICK_SPACING"]["notice"] =~ "sign-extended"
    assert Enum.map(by_name["MAX_REACHABLE_RAISE"]["outputs"], & &1["type"]) == ["uint128"]
    assert Enum.map(by_name["POOL_FEE"]["outputs"], & &1["type"]) == ["uint24"]
  end

  test "final C5 evidence is digest-pinned and admitted for nothing in production" do
    admission = admission!()
    evidence = Map.new(admission["reviewed_action_evidence"], &{&1["contract_id"], &1})

    for {contract_id, digest} <- [
          {"regents_autolaunch_factory_v1", @factory_abi_sha256},
          {"regent_lbp_strategy_v1", @strategy_abi_sha256},
          {"regent_erc20", @erc20_approve_abi_sha256}
        ] do
      entry = Map.fetch!(evidence, contract_id)
      path = Path.join([@root, "contracts", entry["abi_path"]])

      assert File.regular?(path)
      assert entry["abi_sha256"] == digest
      assert Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) == digest

      for action_id <- entry["action_ids"] do
        refute "#{contract_id}.#{action_id}" in admission["admitted_prepared_actions"]
      end
    end

    # Both launch evidence topics are independent Keccak-256 derivations.
    factory = Map.fetch!(evidence, "regents_autolaunch_factory_v1")

    assert factory["confirmation_event_signatures"] == [
             AshPlatform.WalletActions.LaunchAbi.signature(:launch_created),
             AshPlatform.WalletActions.LaunchAbi.signature(:launch_fee_collected)
           ]

    for signature <- factory["confirmation_event_signatures"] do
      assert keccak(signature) ==
               AshPlatform.WalletActions.LaunchAbi.selector(launch_event_id(signature))
    end
  end

  defp launch_event_id("LaunchCreated" <> _rest), do: :launch_created
  defp launch_event_id("LaunchFeeCollected" <> _rest), do: :launch_fee_collected

  defp admission!,
    do:
      @root
      |> Path.join("contracts/chain-contracts.yaml")
      |> YamlElixir.read_from_file!()
      |> Map.fetch!("contracts")
      |> List.first()

  defp consumer_abi(file),
    do: @root |> Path.join("contracts/abi") |> Path.join(file) |> File.read!() |> Jason.decode!()

  defp event_id("Staked" <> _rest), do: :staked
  defp event_id("Unstaked" <> _rest), do: :unstaked
  defp event_id("Claimed" <> _rest), do: :claimed
  defp event_id("PaymentRouted" <> _rest), do: :payment_routed
  defp event_id("ReceiverNoteUpdated" <> _rest), do: :receiver_note_updated

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

  # The evidence manifests stay byte-for-byte frozen, so the one staking read the
  # encoder needs beyond them is proved against the pinned ABI and against an
  # independent Foundry derivation rather than against the encoder itself.
  test "the local staking capacity read matches the pinned ABI and an independent derivation" do
    signature = AshPlatform.WalletActions.Abi.supply_denominator_signature()
    assert signature == "revenueShareSupplyDenominator()"

    cast = System.find_executable("cast") || flunk("Foundry cast is required for chain checks")
    {selector, 0} = System.cmd(cast, ["sig", signature], stderr_to_stdout: true)

    assert String.trim(selector) == AshPlatform.WalletActions.Abi.encode_supply_denominator()
    assert String.trim(selector) == "0xe3961f2a"

    declaration =
      @root
      |> Path.join("contracts/abi/regent-revenue-staking.json")
      |> File.read!()
      |> Jason.decode!()
      |> Enum.find(&(&1["name"] == "revenueShareSupplyDenominator"))

    assert declaration["type"] == "function"
    assert declaration["inputs"] == []
    assert declaration["stateMutability"] == "view"
    assert Enum.map(declaration["outputs"], & &1["type"]) == ["uint256"]
  end

  # Every topic the confirmation path decodes is derived from its exact deployed
  # signature, and proved here against Foundry rather than against itself.
  test "every decoded event topic is an independent Keccak-256 of its deployed signature" do
    staking =
      Map.new(
        [
          :approval,
          :stake_updated,
          :usdc_reward_claimed,
          :reward_token_claimed,
          :reward_token_compounded
        ],
        &{AshPlatform.WalletActions.Abi.event_signature(&1),
         AshPlatform.WalletActions.Abi.event_topic(&1)}
      )

    redemption =
      Map.new(
        [:approval_for_all, :redeemed, :claimed],
        &{AshPlatform.WalletActions.RedemptionAbi.event_signature(&1),
         AshPlatform.WalletActions.RedemptionAbi.event_topic(&1)}
      )

    for {signature, topic} <- Map.merge(staking, redemption) do
      assert keccak(signature) == topic, "#{signature} topic0 disagrees with cast keccak"
    end

    assert staking["StakeUpdated(address,uint256,uint256)"]
    assert staking["RewardTokenCompounded(address,uint256,uint256,uint256)"]
    assert redemption["Redeemed(address,address,uint256,uint256)"]
    assert redemption["Claimed(address,uint256)"]
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
