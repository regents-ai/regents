defmodule AshPlatform.WalletActions.ManifestTest do
  use ExUnit.Case, async: true

  @manifest_path "contracts/base-mainnet.json"
  @chain_manifest_path "contracts/chain-contracts.yaml"
  @abis %{
    "regent_revenue_staking" => %{
      "path" => "abi/regent-revenue-staking.json",
      "sha256" => "c8c5570f76f32b72e3bdb0a062fc97cb7f74aacadf03683d796b57a765f1ca23"
    },
    "animata_redeemer" => %{
      "path" => "abi/animata-redeemer.json",
      "sha256" => "c14a490d3feefbee76fd08e5f993d987e27388cb6c78f4643e2d8010c34766fd"
    }
  }
  @actions %{
    "regent_revenue_staking" => %{
      "stake" => {"stake(uint256,address)", "0x7acb7757"},
      "unstake" => {"unstake(uint256,address)", "0x8381e182"},
      "claim_usdc" => {"claimUSDC(address)", "0x42852610"},
      "claim_regent" => {"claimRegent(address)", "0x739c8d0d"},
      "claim_and_restake_regent" => {"claimAndRestakeRegent()", "0xe72a8732"}
    },
    "animata_redeemer" => %{
      "approve_nft_collection" => {"setApprovalForAll(address,bool)", "0xa22cb465"},
      "approve_exact_usdc" => {"approve(address,uint256)", "0x095ea7b3"},
      "redeem" => {"redeem(address,uint256)", "0x1e9a6950"},
      "claim" => {"claim()", "0x4e71d92d"}
    }
  }
  # The bidder interface stays reviewed and digest-pinned while no bidder action
  # is admitted, so these are proved against the pinned ABI without admitting one.
  @bidder_actions %{
    "continuous_clearing_auction" => %{
      "submit_bid" => {"submitBid(uint256,uint128,address,uint256,bytes)", "0xa52c8728"}
    },
    "permit2" => %{
      "approve" => {"approve(address,address,uint160,uint48)", "0x87517c45"}
    },
    "quote_token_erc20" => %{
      "approve_exact" => {"approve(address,uint256)", "0x095ea7b3"}
    }
  }
  @admitted_actions [
    "regent_revenue_staking.stake",
    "regent_revenue_staking.unstake",
    "regent_revenue_staking.claim_usdc",
    "regent_revenue_staking.claim_regent",
    "regent_revenue_staking.claim_and_restake_regent"
  ]
  # The clean-V1 subject wallet interface stays reviewed and digest-pinned while
  # no subject action is admitted, so these are proved against the derived C1 ABI
  # without admitting one.
  @retained_evidence_actions %{
    "subject_token_erc20" => %{
      "approve_exact" => {"approve(address,uint256)", "0x095ea7b3"}
    },
    "subject_splitter_v1" => %{
      "stake" => {"stake(uint256)", "0xa694fc3a"},
      "unstake" => {"unstake(uint256)", "0x2e17de78"},
      "claim" => {"claim(address)", "0x1e83409a"},
      "claim_all" => {"claimAll()", "0xd1058e59"}
    },
    "payment_receiver_v1" => %{
      "pay" => {"pay(address,uint256,bytes32)", "0x5e5571ac"},
      "sweep" => {"sweep(address,bytes32)", "0x8a738683"},
      "set_receiver_note" => {"setReceiverNote(bytes32)", "0xb1379b2f"}
    }
  }

  # Every executable path and ABI file the superseded subject-payment lane needed.
  # None of them may exist anywhere in the manifest or on disk.
  @deleted_evidence ~w(payment_link_factory revenue_ingress_account revenue_share_splitter_v2)
  @deleted_abis ~w(
    abi/payment-link-factory.json
    abi/revenue-ingress-account.json
    abi/revenue-share-splitter-v2.json
  )
  @deleted_signatures [
    "createPaymentLink(bytes32,string,bytes32)",
    "createCanonicalPaymentLink(bytes32,string,bytes32)",
    "setPaymentLinkCanonical(address,bool)",
    "setPaymentLinkReceiverState(address,bool,address)",
    "sweepUSDC(bytes32)",
    "stake(uint256,address)",
    "unstake(uint256,address)",
    "claimUSDC(address)"
  ]

  test "every pinned ABI path and digest closes over the manifest" do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()

    for {id, expected} <- @abis do
      abi = manifest["contracts"][id]["abi"]
      assert abi["path"] == expected["path"]
      assert abi["canonical_sha256"] == expected["sha256"]
      abi_path = Path.join("contracts", expected["path"])
      assert File.regular?(abi_path)
      assert sha256(File.read!(abi_path)) == expected["sha256"]
    end
  end

  test "pinned ABIs contain every prepared-action signature and selector" do
    manifest = @manifest_path |> File.read!() |> Jason.decode!()

    for {id, expected_actions} <- @actions do
      contract = manifest["contracts"][id]

      actual =
        Map.new(contract["prepared_actions"], &{&1["id"], {&1["signature"], &1["selector"]}})

      assert actual == expected_actions
      abi_path = Path.join("contracts", @abis[id]["path"])
      abi = abi_path |> File.read!() |> Jason.decode!()

      for {_action_id, {signature, _selector}} <- expected_actions,
          signature not in ["setApprovalForAll(address,bool)", "approve(address,uint256)"] do
        assert signature_present?(abi, signature)
      end
    end
  end

  test "declared chain validation closes over every evidence entry and admitted action" do
    chain_manifest = YamlElixir.read_from_file!(@chain_manifest_path)

    for admission <- chain_manifest["contracts"] do
      evidence_path = Path.join("contracts", admission["evidence_manifest"])
      assert File.regular?(evidence_path)
      assert sha256(File.read!(evidence_path)) == admission["evidence_sha256"]

      assert admission["validation_command"] ==
               "mix test test/ash_platform/wallet_actions/manifest_test.exs"

      evidence = Map.new(admission["reviewed_action_evidence"], &{&1["contract_id"], &1})

      # The five reviewed staking actions are admitted, each resolving to the
      # evidence entry that reviewed it; nothing else is.
      assert admission["admitted_prepared_actions"] == @admitted_actions

      for dotted <- @admitted_actions do
        [contract_id, action_id] = String.split(dotted, ".", parts: 2)
        assert action_id in Map.fetch!(evidence, contract_id)["action_ids"]
      end

      for {id, entry} <- evidence do
        abi_path = Path.join("contracts", entry["abi_path"])
        assert File.regular?(abi_path)
        assert sha256(File.read!(abi_path)) == entry["abi_sha256"]

        expected_actions =
          Map.get(@actions, id) ||
            Map.get(@bidder_actions, id) ||
            Map.fetch!(@retained_evidence_actions, id)

        assert MapSet.new(entry["action_ids"]) == MapSet.new(Map.keys(expected_actions))
      end

      for {contract_id, actions} <- @bidder_actions,
          {action_id, {signature, selector}} <- actions do
        entry = Map.fetch!(evidence, contract_id)
        assert action_id in entry["action_ids"]

        abi = "contracts" |> Path.join(entry["abi_path"]) |> File.read!() |> Jason.decode!()

        assert signature_present?(abi, signature)
        assert selector_for(signature) == selector
      end

      auction = Map.fetch!(evidence, "continuous_clearing_auction")
      assert auction["source_commit"] == "7d7602d257733315434570f2a0c2f94f1c7b207a"
      assert auction["interface_note"] =~ "canonical five-argument submitBid"
      assert auction["interface_note"] =~ "collects a non-native currency only through Permit2"
      refute auction["interface_note"] =~ "four-argument convenience overload"

      permit2 = Map.fetch!(evidence, "permit2")
      assert permit2["address"] == "0x000000000022D473030F116dDEE9F6B43aC78BA3"
      assert permit2["address_provenance"] =~ "2af06408b6a204824c2ecb245779ed400b535fb5"
      assert permit2["address_provenance"] =~ "src/utils/SafeTransferLib.sol line 64"

      # The C1 evidence is pinned to the exact integrated contract source.
      for contract_id <- ["subject_splitter_v1", "payment_receiver_v1"] do
        entry = Map.fetch!(evidence, contract_id)
        assert entry["source_commit"] == "59e1f0c195428f9d74b72223d154e1fee693c36d"
        assert entry["source_tree"] == "d1b3d5a75ce84fe7ee042a85c9b79a91e842cc6d"
      end

      # The superseded lane leaves no evidence entry and no admitted action.
      for contract_id <- @deleted_evidence do
        refute Map.has_key?(evidence, contract_id)
      end
    end
  end

  test "the superseded subject-payment ABI evidence is gone from the manifest and from disk" do
    manifest = File.read!(@chain_manifest_path)

    for contract_id <- @deleted_evidence do
      refute manifest =~ contract_id
    end

    for abi_path <- @deleted_abis do
      refute manifest =~ abi_path
      refute File.exists?(Path.join("contracts", abi_path))
    end

    # The subject lane's own ABI files declare none of the superseded shapes.
    # `regent-revenue-staking.json` is deliberately not swept: the live global
    # REGENT contract really does declare stake(uint256,address),
    # unstake(uint256,address) and claimUSDC(address), and this ticket does not
    # touch that separately certified lane.
    for path <- [
          "contracts/abi/subject-splitter-v1.json",
          "contracts/abi/payment-receiver-v1.json"
        ],
        signature <- @deleted_signatures do
      abi = path |> File.read!() |> Jason.decode!()
      refute signature_present?(abi, signature), "#{path} still declares #{signature}"
    end
  end

  test "every admitted C1 selector is an independent Foundry derivation of its declared signature" do
    chain_manifest = YamlElixir.read_from_file!(@chain_manifest_path)

    evidence =
      chain_manifest["contracts"]
      |> List.first()
      |> Map.fetch!("reviewed_action_evidence")
      |> Map.new(&{&1["contract_id"], &1})

    for {contract_id, actions} <-
          Map.take(@retained_evidence_actions, [
            "subject_splitter_v1",
            "payment_receiver_v1"
          ]),
        {action_id, {signature, selector}} <- actions do
      entry = Map.fetch!(evidence, contract_id)
      assert action_id in entry["action_ids"]

      abi = "contracts" |> Path.join(entry["abi_path"]) |> File.read!() |> Jason.decode!()
      assert signature_present?(abi, signature)
      assert selector_for(signature) == selector

      # And it is not admitted for production preparation.
      refute "#{contract_id}.#{action_id}" in @admitted_actions
    end
  end

  defp signature_present?(abi, signature) do
    Enum.any?(abi, fn entry ->
      if entry["type"] == "function" do
        candidate =
          entry["name"] <> "(" <> Enum.map_join(entry["inputs"], ",", & &1["type"]) <> ")"

        candidate == signature
      else
        false
      end
    end)
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp selector_for(signature) do
    cast = System.find_executable("cast") || flunk("Foundry cast is required for chain checks")
    {selector, 0} = System.cmd(cast, ["sig", signature], stderr_to_stdout: true)
    String.trim(selector)
  end
end
