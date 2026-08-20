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
  # The bidder interface stays reviewed and digest-pinned while nothing is
  # admitted, so these are proved against the pinned ABI without admitting one.
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
  @retained_evidence_actions %{
    "payment_link_factory" => %{
      "create_payment_link" => {"createPaymentLink(bytes32,string,bytes32)", "0x96bc6c1a"},
      "create_canonical_payment_link" =>
        {"createCanonicalPaymentLink(bytes32,string,bytes32)", "0xb12d629e"},
      "set_payment_link_canonical" => {"setPaymentLinkCanonical(address,bool)", "0x706a7fa6"},
      "set_payment_link_receiver_state" =>
        {"setPaymentLinkReceiverState(address,bool,address)", "0xc8c05f99"}
    },
    "revenue_ingress_account" => %{
      "sweep_usdc" => {"sweepUSDC(bytes32)", "0xbe25fb30"}
    },
    "subject_token_erc20" => %{
      "approve_exact" => {"approve(address,uint256)", "0x095ea7b3"}
    },
    "revenue_share_splitter_v2" => %{
      "stake" => {"stake(uint256,address)", "0x7acb7757"},
      "unstake" => {"unstake(uint256,address)", "0x8381e182"},
      "claim_usdc" => {"claimUSDC(address)", "0x42852610"}
    }
  }

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

      # Nothing is admitted while the runtime, predecessor source, projection and
      # entitlement bindings are unfrozen.
      assert admission["admitted_prepared_actions"] == []

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
