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
    "regent_revenue_staking.claim_and_restake_regent",
    "animata_redeemer.approve_nft_collection",
    "animata_redeemer.approve_exact_usdc",
    "animata_redeemer.redeem",
    "animata_redeemer.claim",
    "regents_club.set_base_uri"
  ]
  # The clean-V1 subject wallet interface stays reviewed and digest-pinned while
  # no subject action is admitted, so these are proved against the final C9 ABI
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
      "sweep" => {"sweep(address)", "0x01681a62"},
      "set_receiver_note" => {"setReceiverNote(bytes32)", "0xb1379b2f"}
    },
    # The final launch interface stays reviewed and digest-pinned while no launch
    # action is admitted for production preparation.
    "regent_erc20" => %{
      "approve_exact" => {"approve(address,uint256)", "0x095ea7b3"}
    },
    "regents_autolaunch_factory_v1" => %{
      "launch" =>
        {"launch((string,string,string,string,string,address,uint128,uint256))", "0xd0464e3e"}
    },
    "regent_lbp_strategy_v1" => %{}
  }

  # The final C9 source fingerprints. The upstream build artifacts these ABIs are
  # derived from are excluded by that repository's own .gitignore, so the durable
  # evidence is the compiler's metadata Keccak-256 of the exact source files,
  # alongside the runtime hashes its own pinned release manifest records.
  @c9_source_commit "f4114f5276386f48bf8dc53ee344189d98c8896e"
  @c9_source_tree "bb660324bb1d5cc322adeb243b0bd51779821fcb"
  @factory_source_keccak256 "0x365a31acbff3ba9e63160e6bf461ae28fe99dd12c7bee1e92f693d3840433108"
  @strategy_source_keccak256 "0x9a757096a5834b3d521933ea5f92ae79ec8633791e28b8f0e2d54af35563d82f"
  @splitter_source_keccak256 "0xb9232cc9efd7a684a40c82d1f0907fdef1e8417d6cb109515cc6e4222b3d92e1"
  @c9_abi_surface_sha256 "ef5dea8e9c9c17cb999a056e3045b72497ab5850a5c82f729fd7f1849df2f7d5"
  @c9_release_manifest_sha256 "6247280e8d0366a051b3b9a8e88de0e2ca25a1fdee358bdce2737581f1e3650b"
  @c9_fork_observations_sha256 "b4636352c25678c32a3a690e3ff1caff0f1a4fd1504844d3ae138fdbced4e2c0"

  # The frozen-artifact runtime hashes each consumer contract must present, and
  # the SubjectSplitterV1 implementation hash the factory itself admits by code
  # hash, all read from that same release manifest.
  @runtime_keccak256 %{
    "regents_autolaunch_factory_v1" =>
      "0xc6a3cc79c3a28e75b30cf55091e921773de32f7798d474712f8e1e24f1a021d4",
    "regent_lbp_strategy_v1" =>
      "0xdfdda2748e2d1ce9f13d99f6b76ea120fec2f8727f9ea97772d0445f8e5b699f",
    "subject_splitter_v1" => "0x51f75aa1524323c76b393e14aa236909badf323187512949d4356163316f749e",
    "payment_receiver_v1" => "0x98088902bc81f8472949dad00e0670d1427cff0ae1bed025120993c9b0c9dfbc"
  }

  # The exact six the strategy refuses as a launch treasury: three read at the
  # reviewed block, three frozen in the contract's own Base bindings.
  @frozen_refused_treasuries [
    %{"id" => "pool_manager", "address" => "0x498581fF718922c3f8e6A244956aF099B2652b2b"},
    %{"id" => "position_manager", "address" => "0x7C5f5A4bBd8fD63184577525326123B519429bDc"},
    %{"id" => "live_staking", "address" => "0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5"}
  ]

  # Everything this consumer lane deliberately does not derive an encoder, action or admission
  # for. None of these may appear anywhere in the manifest or in either ABI file.
  @absent_consumer_surfaces ~w(
    setLaunchFee
    pauseLaunches
    unpauseLaunches
    createPaymentReceiver
    bindHook
    initializeDistribution
    migrate
  )

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

      # The retained consumer evidence is pinned to the exact final contract source
      # and to the runtime hash that build's own release manifest records.
      for {contract_id, runtime_keccak256} <- @runtime_keccak256 do
        entry = Map.fetch!(evidence, contract_id)
        assert entry["source_commit"] == @c9_source_commit
        assert entry["source_tree"] == @c9_source_tree
        assert entry["runtime_keccak256"] == runtime_keccak256
      end

      assert Map.fetch!(evidence, "subject_splitter_v1")["implementation_provenance"] =~
               @splitter_source_keccak256

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

  test "every retained C9 selector is an independent Foundry derivation of its declared signature" do
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

  test "the final C9 launch evidence pins its source fingerprints and admits no production action" do
    evidence = evidence!()

    factory = Map.fetch!(evidence, "regents_autolaunch_factory_v1")
    strategy = Map.fetch!(evidence, "regent_lbp_strategy_v1")

    for entry <- [factory, strategy] do
      assert entry["source_commit"] == @c9_source_commit
      assert entry["source_tree"] == @c9_source_tree
      assert entry["artifact_provenance"] =~ ".gitignore excludes"
      assert entry["artifact_provenance"] =~ "not a tracked file"
    end

    assert factory["source_keccak256"] == @factory_source_keccak256
    assert strategy["source_keccak256"] == @strategy_source_keccak256
    assert factory["target"] == "c5_admitted_factory_address"
    assert strategy["target"] == "reviewed_factory_bound_strategy_address"
    assert strategy["action_ids"] == []

    # The factory admits the splitter implementation by exact runtime code hash,
    # so the consumer freeze records that binding alongside the factory's own.
    assert factory["factory_bound_splitter_runtime_keccak256"] ==
             @runtime_keccak256["subject_splitter_v1"]

    # The one strategy read this lane performs, and the three frozen identities
    # that complete the exact six a launch treasury may not be.
    assert strategy["reads"] == [
             %{"id" => "hook", "signature" => "hook()", "selector" => "0x7f5a7c7b"}
           ]

    assert strategy["refused_launch_treasuries"] == @frozen_refused_treasuries

    assert strategy["refused_launch_treasury_provenance"] =~
             "BaseBindings.sol lines 19, 20 and 21"

    # The exact allowance rule the fee correction follows, and no other spender.
    regent = Map.fetch!(evidence, "regent_erc20")
    assert regent["target"] == "pinned_regent_token_address"
    assert regent["action_ids"] == ["approve_exact"]
    assert regent["interface_note"] =~ "exact current launch fee"
    assert regent["interface_note"] =~ "no unlimited approval"

    # Every final action id is reviewed evidence and none of them is admitted for
    # production preparation: deployment evidence must open that gate later.
    admitted = admission!()["admitted_prepared_actions"]
    assert admitted == @admitted_actions

    for contract_id <- ["regents_autolaunch_factory_v1", "regent_lbp_strategy_v1", "regent_erc20"],
        action_id <- Map.fetch!(evidence, contract_id)["action_ids"] do
      refute "#{contract_id}.#{action_id}" in admitted
    end
  end

  test "the launch tuple signature canonicalizes to the one literal the encoder holds" do
    entry = Map.fetch!(evidence!(), "regents_autolaunch_factory_v1")
    abi = "contracts" |> Path.join(entry["abi_path"]) |> File.read!() |> Jason.decode!()
    declared = Enum.find(abi, &(&1["name"] == "launch"))

    # The canonicalization is the manifest task's existing one, so the literal in
    # `LaunchAbi` is proved against a second implementation rather than itself.
    signature = Mix.Tasks.AshPlatform.VerifyChainManifest.canonical_signature(declared)

    assert signature == AshPlatform.WalletActions.LaunchAbi.signature(:launch)
    assert selector_for(signature) == AshPlatform.WalletActions.LaunchAbi.selector(:launch)
    assert selector_for(signature) == "0xd0464e3e"
  end

  test "no governance, receiver, construction or migration surface is derived by the consumer lane" do
    for path <- [
          "contracts/abi/regents-autolaunch-factory-v1.json",
          "contracts/abi/regent-lbp-strategy-v1.json"
        ] do
      abi = path |> File.read!() |> Jason.decode!()
      names = MapSet.new(abi, & &1["name"])

      for surface <- @absent_consumer_surfaces do
        refute MapSet.member?(names, surface), "#{path} still declares #{surface}"
      end
    end

    # Absent from the ABI files is not enough: no evidence entry anywhere in the
    # manifest may carry one as an action id either.
    declared =
      evidence!() |> Map.values() |> Enum.flat_map(&(&1["action_ids"] || [])) |> MapSet.new()

    for surface <- @absent_consumer_surfaces do
      refute MapSet.member?(declared, surface)
    end

    factory = Map.fetch!(evidence!(), "regents_autolaunch_factory_v1")
    assert factory["interface_note"] =~ "deliberately not derived"
    assert Map.fetch!(evidence!(), "regent_lbp_strategy_v1")["interface_note"] =~ "never reaches"
  end

  defp evidence!,
    do: Map.new(admission!()["reviewed_action_evidence"], &{&1["contract_id"], &1})

  defp admission!,
    do: @chain_manifest_path |> YamlElixir.read_from_file!() |> Map.fetch!("contracts") |> hd()

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
