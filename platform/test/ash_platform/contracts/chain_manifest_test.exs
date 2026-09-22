defmodule AshPlatform.Contracts.ChainManifestTest do
  use ExUnit.Case, async: true

  alias AshPlatform.WalletActions.Abi

  @root Path.expand("../../..", __DIR__)
  @manifest_path Path.join(@root, "contracts/base-mainnet.json")
  @staking_abi_sha256 "c8c5570f76f32b72e3bdb0a062fc97cb7f74aacadf03683d796b57a765f1ca23"
  @redeemer_abi_sha256 "c14a490d3feefbee76fd08e5f993d987e27388cb6c78f4643e2d8010c34766fd"
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
             "set_approval_for_all",
             "total_supply"
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

  test "chain admission admits only the staking and redemption actions" do
    admission =
      @root
      |> Path.join("contracts/chain-contracts.yaml")
      |> YamlElixir.read_from_file!()
      |> get_in(["contracts"])
      |> List.first()

    assert admission["authority"] == "evidence_only"

    assert admission["admitted_prepared_actions"] == [
             "regent_revenue_staking.stake",
             "regent_revenue_staking.unstake",
             "regent_revenue_staking.claim_usdc",
             "regent_revenue_staking.claim_regent",
             "regent_revenue_staking.claim_and_restake_regent",
             "animata_redeemer.approve_nft_collection",
             "animata_redeemer.approve_exact_usdc",
             "animata_redeemer.redeem",
             "animata_redeemer.claim"
           ]

    evidence = Map.new(admission["reviewed_action_evidence"], &{&1["contract_id"], &1})

    # Every reviewed contract other than the two admitted purpose-specific ones
    # is absent.
    for {contract_id, entry} <- evidence,
        contract_id not in ["regent_revenue_staking", "animata_redeemer"],
        action_id <- entry["action_ids"] do
      refute "#{contract_id}.#{action_id}" in admission["admitted_prepared_actions"]
    end
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

  defp admission!,
    do:
      @root
      |> Path.join("contracts/chain-contracts.yaml")
      |> YamlElixir.read_from_file!()
      |> Map.fetch!("contracts")
      |> List.first()

  defp consumer_abi(file),
    do: @root |> Path.join("contracts/abi") |> Path.join(file) |> File.read!() |> Jason.decode!()

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
