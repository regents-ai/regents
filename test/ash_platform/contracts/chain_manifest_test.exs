defmodule AshPlatform.Contracts.ChainManifestTest do
  use ExUnit.Case, async: true

  alias AshPlatform.WalletActions.Abi

  @root Path.expand("../../..", __DIR__)
  @manifest_path Path.join(@root, "contracts/base-mainnet.json")
  @staking_abi_sha256 "c8c5570f76f32b72e3bdb0a062fc97cb7f74aacadf03683d796b57a765f1ca23"
  @redeemer_abi_sha256 "c14a490d3feefbee76fd08e5f993d987e27388cb6c78f4643e2d8010c34766fd"
  @auction_abi_sha256 "f687d42ad0fd981e38ba7f43baad6428014f5056a129a7bf13906f5704e5194b"
  @permit2_abi_sha256 "ced6a1b558e80e4a80c5bc1920da8cca21fa63806ac379b5c1c8ab4b6c866832"
  @bid_submitted_signature "BidSubmitted(uint256,address,uint256,uint128)"
  @bid_submitted_topic0 "0x650baad5cd8ca09b8f580be220fa04ce2ba905a041f764b6a3fe2c848eb70540"
  @erc20_approve_abi_sha256 "c3b0ea0f4cb03cf09bee2ef0ea451c976bcfb13c658f5f6d37784699d567efec"
  @subject_splitter_abi_sha256 "90d42d515ffec4973e42d926ac84e62d001612677c9eeac1360f87940568fc49"
  @payment_receiver_abi_sha256 "4c297d2200b17c6253861ad699c7f03f0f97491c30632cc9f7b90daeb1c1fc3b"
  @factory_abi_sha256 "f2800add2b781fc7353a670f87914118c47bea3856df17dcdb3de2af42fd5eba"
  @strategy_abi_sha256 "f0294ec55ba24f897be5618a675e5871aa7439e879de91e69392fabc452f650c"
  @c9_source_commit "0fa0bc49429d43258d57836b478aa5943366942a"
  @c9_source_tree "3f11b0a6ceb295ee9455f580003d7bdaac09f954"
  @c9_abi_surface_sha256 "ef5dea8e9c9c17cb999a056e3045b72497ab5850a5c82f729fd7f1849df2f7d5"
  @c9_release_manifest_sha256 "6247280e8d0366a051b3b9a8e88de0e2ca25a1fdee358bdce2737581f1e3650b"
  @c9_fork_observations_sha256 "86be9f50d64699411b2f09746fa5b6e9757b250095f1ce4a09a230e06d0bbbc6"
  @multicall3_abi_sha256 "37abf10ee8402b89482af88b281653256b79eb6d96eb4599200c03f542d8689d"
  @multicall3_address "0xcA11bde05977b3631167028862bE2a173976CA11"
  @multicall3_runtime_keccak256 "0xd5c15df687b16f2ff992fc8d767b4216323184a2bbc6ee2f9c398c318e770891"
  @multicall3_runtime_sha256 "2756d7c52baee85cacb504f6ee1df7aad6809ac8d94a4a111d76991f90d36d6e"
  @multicall3_runtime_bytes 3808
  @aggregate3_signature "aggregate3((address,bool,bytes)[])"
  @aggregate3_selector "0x82ad56cb"

  # The reading aggregator is not part of any send path. These are the modules
  # that build prepared actions and confirm them, and none of them may so much
  # as name it.
  @send_path_modules [
    "lib/ash_platform/wallet_actions/envelope.ex",
    "lib/ash_platform/staking/actions.ex",
    "lib/ash_platform/redemption/actions.ex"
  ]

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

  test "chain admission admits the staking and redemption actions while the bidder interface stays evidence" do
    admission =
      @root
      |> Path.join("contracts/chain-contracts.yaml")
      |> YamlElixir.read_from_file!()
      |> get_in(["contracts"])
      |> List.first()

    assert admission["authority"] == "evidence_only"

    assert admission["autolaunch_consumer_freeze"] == %{
             "repository" => "autolaunch-contracts",
             "source_commit" => @c9_source_commit,
             "source_tree" => @c9_source_tree,
             "abi_surface_sha256" => @c9_abi_surface_sha256,
             "release_manifest_sha256" => @c9_release_manifest_sha256,
             "fork_observations_sha256" => @c9_fork_observations_sha256,
             "deployment_status" => "deployment_pending",
             "admission" => "disabled"
           }

    assert admission["admitted_prepared_actions"] == [
             "regent_revenue_staking.stake",
             "regent_revenue_staking.unstake",
             "regent_revenue_staking.claim_usdc",
             "regent_revenue_staking.claim_regent",
             "regent_revenue_staking.claim_and_restake_regent",
             "animata_redeemer.approve_nft_collection",
             "animata_redeemer.approve_exact_usdc",
             "animata_redeemer.redeem",
             "animata_redeemer.claim",
             "regents_club.set_base_uri"
           ]

    evidence = Map.new(admission["reviewed_action_evidence"], &{&1["contract_id"], &1})

    # Every reviewed contract other than the three admitted purpose-specific ones,
    # including every Autolaunch one, is absent.
    for {contract_id, entry} <- evidence,
        contract_id not in ["regent_revenue_staking", "animata_redeemer", "regents_club"],
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
    assert subject_erc20["implementation_provenance"] =~ @c9_source_commit
    assert subject_erc20["implementation_provenance"] =~ "SubjectSplitterV1.sol:66"
    assert subject_erc20["implementation_provenance"] =~ "exact splitter spender"

    assert splitter["contract_name"] == "SubjectSplitterV1"
    assert splitter["target"] == "stored_subject_splitter_address"
    assert splitter["action_ids"] == ["stake", "unstake", "claim", "claim_all"]
    assert splitter["implementation_provenance"] =~ "SubjectSplitterV1.sol"
    assert splitter["implementation_provenance"] =~ "lines 201-250"
    assert splitter["interface_note"] =~ "no recipient-argument overload and no"
    assert splitter["interface_note"] =~ "truthful no-op"

    # The two facts pinned about that same surface: supply-proportional coverage,
    # and an exit delay that now covers every path value can leave an account by.
    assert splitter["interface_note"] =~ "complete 100-billion"
    assert splitter["interface_note"] =~ "leaves the treasury the exact"
    assert splitter["interface_note"] =~ "refuse an unstake, a claim and a claim-all alike in"
    assert splitter["interface_note"] =~ "no getter"

    assert receiver["contract_name"] == "PaymentReceiverV1"
    assert receiver["target"] == "projected_canonical_receiver_address"
    assert receiver["action_ids"] == ["pay", "sweep", "set_receiver_note"]
    assert receiver["implementation_provenance"] =~ "PaymentReceiverV1.sol"
    assert receiver["interface_note"] =~ "referralBps() is 0"
    assert receiver["interface_note"] =~ "projected canonical_receiver_address"

    # A sweep names only the token, and the reference its routing event carries is
    # the zero word the receiver itself supplies.
    assert receiver["implementation_provenance"] =~ "Sweep takes only the token"
    assert receiver["implementation_provenance"] =~ "zero payment reference"

    # Both entries pin the exact integrated contract source and tree.
    for entry <- [splitter, receiver] do
      assert entry["source_commit"] == @c9_source_commit
      assert entry["source_tree"] == @c9_source_tree
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

  # The final C9 ABI is derived from exact pinned source, so the shapes this lane
  # encodes and decodes are proved against the file rather than assumed.
  test "the final C9 splitter ABI declares exactly the caller-only customer surface" do
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

    for entry <- abi, do: assert(entry["notice"] =~ @c9_source_commit)
  end

  test "the final C9 receiver ABI declares exactly the payment surface and its two events" do
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
    # A sweep names only the token; the routed reference is the receiver's own zero.
    assert Enum.map(by_name["sweep"]["inputs"], & &1["type"]) == ["address"]
    assert by_name["sweep"]["notice"] =~ "under the zero payment reference"
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

    for entry <- abi, do: assert(entry["notice"] =~ @c9_source_commit)
  end

  # The final C9 ABI is derived from exact pinned source, so the shapes this lane
  # encodes and decodes are proved against the file rather than assumed.
  test "the final C9 factory ABI declares exactly the one customer call and its review reads" do
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
    assert [%{"type" => "tuple"}] = by_name["launch"]["inputs"]
    assert by_name["launch"]["stateMutability"] == "nonpayable"

    # Reads are reads and the approval is a mutation; nothing here blurs them.
    for name <- ["launchFee", "launchesPaused", "strategy", "launches", "launchIdOfSubject"] do
      assert by_name[name]["stateMutability"] == "view"
    end

    assert [%{"type" => "tuple", "components" => record}] = by_name["launches"]["outputs"]
    assert Enum.map(record, & &1["type"]) == List.duplicate("address", 5)

    # Three indexed identities, then the treasury, the raise and the fixed
    # schedule in exactly the data words the decoder reads positionally.
    assert Enum.count(by_name["LaunchCreated"]["inputs"], & &1["indexed"]) == 3

    assert by_name["LaunchCreated"]["inputs"]
           |> Enum.drop(3)
           |> Enum.map(&{&1["name"], &1["type"], &1["indexed"]}) == [
             {"auction", "address", false},
             {"escrow", "address", false},
             {"treasury", "address", false},
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

    for entry <- abi, do: assert(entry["notice"] =~ @c9_source_commit)
  end

  test "the final C9 strategy ABI declares only its two identities and the frozen terms" do
    abi = consumer_abi("regent-lbp-strategy-v1.json")

    assert Enum.map(abi, & &1["name"]) == [
             "factory",
             "hook",
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
      assert entry["notice"] =~ @c9_source_commit
    end

    # The read that supplies one of the exact six refused launch treasuries.
    assert by_name["hook"]["notice"] =~ "refuse it, the factory and this strategy as a launch"

    # The one signed term, and the one whose word therefore needs bringing back.
    assert Enum.map(by_name["POOL_TICK_SPACING"]["outputs"], & &1["type"]) == ["int24"]
    assert by_name["POOL_TICK_SPACING"]["notice"] =~ "sign-extended"
    assert Enum.map(by_name["MAX_REACHABLE_RAISE"]["outputs"], & &1["type"]) == ["uint128"]
    assert Enum.map(by_name["POOL_FEE"]["outputs"], & &1["type"]) == ["uint24"]
  end

  test "final C9 evidence is digest-pinned and admitted for nothing in production" do
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

  test "Regents Club admits one exact forward metadata cutover with independent evidence", %{
    manifest: manifest
  } do
    contract = manifest["contracts"]["regents_club"]
    abi_digest = "05e58830ff8454bdd0b0130b96d2a59b350802ef79a1d540f743c44107ff1be2"

    calldata =
      "0x55f804b30000000000000000000000000000000000000000000000000000000000000020" <>
        "0000000000000000000000000000000000000000000000000000000000000022" <>
        "68747470733a2f2f6d656469612e726567656e74732e73682f6d657461646174612f" <>
        String.duplicate("0", 60)

    assert contract["address"] == "0x2208aaDBdEcd47D3B4430b5b75a175f6d885D487"
    assert contract["abi"]["canonical_sha256"] == abi_digest
    assert contract["runtime_code"]["bytes"] == 19_658

    assert contract["runtime_code"]["keccak256"] ==
             "0x69e7a7158f30acb817dc83a4e21af19a216c3a2ae57db423599ca82f321e3041"

    constants = contract["onchain_constants"]
    assert constants["owner"] == "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
    assert constants["total_supply"] == 1998
    assert constants["erc4906_interface_id"] == "0x49064906"
    assert constants["current_base_uri"] <> "1" == "https://regents.sh/metadata/1"
    assert constants["current_base_uri"] <> "1998" == "https://regents.sh/metadata/1998"
    assert constants["calldata_keccak256"] == keccak(calldata)

    media = contract["media_release_attestation"]

    assert media == %{
             "active_image_digest" =>
               "sha256:03b40ae0c61d28bbc0c28b62032d3cb1a0c7c41d09bb1e46ed6327a0f10353f6",
             "artifact_manifest_sha256" =>
               "493d99596cd8ab2cdeae1d1bbafac20aa216470c95bdad25cbc4db163e3a4c6a",
             "release_manifest_sha256" =>
               "356352b67b6338ec0b19595d1c0140bf8052756a793163a95a3071ef25a52789",
             "production_deployment_verification_sha256" =>
               "6bb8a3e812222a29b1551470a7a18d8c715130102c7535dd73ed62d611dfa727",
             "isolated_verification_sha256" =>
               "52ed1913b9160d41981614687253a33ed7d437a793a8c4ec154004afc25143bd",
             "full_corpus_route_count" => 1998,
             "live_probe_token_ids" => [1, 1000, 1998],
             "operator_attestation_required" => true
           }

    admission = admission!()

    evidence =
      Enum.find(admission["reviewed_action_evidence"], &(&1["contract_id"] == "regents_club"))

    assert evidence["media_release_attestation"] == media

    assert contract["prepared_actions"] == [
             %{
               "id" => "set_base_uri",
               "signature" => "setBaseURI(string)",
               "selector" => "0x55f804b3",
               "value" => "0",
               "signer_class" => "exact_regents_club_owner",
               "beneficiary_class" => "regents_club_collection",
               "argument_bindings" => %{
                 "new_base_uri" => "https://media.regents.sh/metadata/",
                 "expected_signer" => "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
               }
             }
           ]

    assert Enum.map(contract["reads"], & &1["signature"]) == [
             "owner()",
             "baseURI()",
             "tokenURI(uint256)",
             "totalSupply()",
             "supportsInterface(bytes4)"
           ]

    assert contract["confirmation_event"] == %{
             "signature" => "BatchMetadataUpdate(uint256,uint256)",
             "topic0" => keccak("BatchMetadataUpdate(uint256,uint256)"),
             "from_token_id" => 1,
             "to_token_id" => 1998
           }

    assert calldata == AshPlatform.RegentsClub.calldata()
    assert_selectors(contract["reads"] ++ contract["prepared_actions"])

    abi_path = Path.join([@root, "contracts", contract["abi"]["path"]])
    assert Base.encode16(:crypto.hash(:sha256, File.read!(abi_path)), case: :lower) == abi_digest
  end

  test "pins the reading aggregator's identity beside the frozen evidence it is not part of" do
    entry =
      admission!()
      |> Map.fetch!("reviewed_action_evidence")
      |> Enum.find(&(&1["contract_id"] == "multicall3"))

    assert entry["contract_name"] == "Multicall3"
    assert entry["target"] == "canonical_multicall3"
    assert entry["address"] == @multicall3_address
    assert entry["runtime_keccak256"] == @multicall3_runtime_keccak256
    assert entry["runtime_sha256"] == @multicall3_runtime_sha256
    assert entry["runtime_bytes"] == @multicall3_runtime_bytes
    assert entry["abi_path"] == "abi/multicall3.json"
    assert entry["abi_sha256"] == @multicall3_abi_sha256

    assert entry["reads"] == [
             %{
               "id" => "aggregate3",
               "signature" => @aggregate3_signature,
               "selector" => @aggregate3_selector
             }
           ]

    # Nothing is prepared against it, and nothing about it is admitted to send.
    assert entry["action_ids"] == []
    assert entry["interface_note"] =~ "reading only"
    assert entry["interface_note"] =~ "never a send target"
    assert entry["address_provenance"] =~ "eth_getCode"

    refute Enum.any?(
             admission!()["admitted_prepared_actions"],
             &String.starts_with?(&1, "multicall3.")
           )
  end

  test "the aggregator ABI copy, its digest and the constants the code reads all agree" do
    digest =
      @root
      |> Path.join("contracts/abi/multicall3.json")
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    assert digest == @multicall3_abi_sha256

    # Trimmed the way every other consumer copy here is: exactly the one
    # function this codebase calls, and nothing else Multicall3 declares.
    abi = consumer_abi("multicall3.json")
    assert [%{"type" => "function", "name" => "aggregate3"}] = abi

    assert Abi.multicall3_address() == @multicall3_address
    assert Abi.multicall3_runtime_keccak256() == @multicall3_runtime_keccak256
    assert Abi.multicall3_runtime_sha256() == @multicall3_runtime_sha256
    assert Abi.multicall3_runtime_bytes() == @multicall3_runtime_bytes
    assert Abi.aggregate3_signature() == @aggregate3_signature
    assert Abi.aggregate3_selector() == @aggregate3_selector
    assert keccak(@aggregate3_signature) |> String.slice(0, 10) == @aggregate3_selector

    # The frozen evidence file carries nothing about the aggregator, and stays
    # exactly as it was.
    manifest = @manifest_path |> File.read!() |> Jason.decode!()
    refute Map.has_key?(manifest["contracts"], "multicall3")
  end

  test "no module that prepares or confirms a transaction so much as names the aggregator" do
    for path <- @send_path_modules do
      source = @root |> Path.join(path) |> File.read!() |> String.downcase()

      refute source =~ "multicall"
      refute source =~ "aggregate3"
      refute source =~ String.downcase(@multicall3_address)
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
