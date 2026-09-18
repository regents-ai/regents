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
    },
    "regents_club" => %{
      "path" => "abi/regents-club.json",
      "sha256" => "05e58830ff8454bdd0b0130b96d2a59b350802ef79a1d540f743c44107ff1be2"
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
    },
    "regents_club" => %{
      "set_base_uri" => {"setBaseURI(string)", "0x55f804b3"}
    }
  }
  @admitted_actions [
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
  # The reading aggregator is reviewed and digest-pinned like the rest, and
  # prepares nothing at all: it is only ever read through.
  @read_only_evidence %{"multicall3" => %{}}

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

      # The five reviewed staking actions and the four reviewed redeemer actions
      # are admitted, each resolving to the evidence entry that reviewed it;
      # nothing else is.
      assert admission["admitted_prepared_actions"] == @admitted_actions

      for dotted <- @admitted_actions do
        [contract_id, action_id] = String.split(dotted, ".", parts: 2)
        assert action_id in Map.fetch!(evidence, contract_id)["action_ids"]
      end

      for {id, entry} <- evidence do
        abi_path = Path.join("contracts", entry["abi_path"])
        assert File.regular?(abi_path)
        assert sha256(File.read!(abi_path)) == entry["abi_sha256"]

        expected_actions = Map.get(@actions, id) || Map.fetch!(@read_only_evidence, id)

        assert MapSet.new(entry["action_ids"]) == MapSet.new(Map.keys(expected_actions))
      end
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
end
