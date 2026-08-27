defmodule AshPlatform.Autolaunch.TreasurySecurityTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch
  alias AshPlatform.TestAutolaunchTreasuryChainClient, as: Client

  @safe "0x9999999999999999999999999999999999999999"

  setup do
    on_exit(fn ->
      Application.delete_env(:ash_platform, :autolaunch_treasury_chain_client)
      Application.delete_env(:ash_platform, :test_autolaunch_treasury_observation)
    end)

    :ok
  end

  test "VERIFIED_MEANS_EXACT_2_OF_3_AND_THREE_HISTORICAL_PROOFS" do
    report = Client.seed_verified!(@safe)

    assert report.classification == :supported_safe
    assert report.verification_state == :verified
    assert report.owner_count == 3
    assert report.threshold == 2
    assert report.modules == []
  end

  test "COMPLETE_EVIDENCE_AT_THE_SAME_BLOCK_CREATES_A_NEW_IMMUTABLE_REPORT" do
    Client.install()

    assert {:ok, incomplete} =
             Autolaunch.observe_treasury_security(@safe, %{}, actor: %System{})

    assert incomplete.verification_state == :unverified

    assert {:ok, complete} =
             Autolaunch.observe_treasury_security(
               @safe,
               %{
                 usdc: "0x" <> String.duplicate("11", 32),
                 regent: "0x" <> String.duplicate("22", 32),
                 outbound: "0x" <> String.duplicate("33", 32)
               },
               actor: %System{}
             )

    assert complete.verification_state == :verified
    assert complete.source_block_hash == incomplete.source_block_hash
    assert complete.configuration_fingerprint == incomplete.configuration_fingerprint
    refute complete.id == incomplete.id

    assert {:ok, unchanged} =
             Autolaunch.get_treasury_security_report(incomplete.id, actor: nil)

    assert unchanged.verification_state == :unverified
  end

  test "EOA_AND_INTERFACE_FREE_CONTRACTS_STAY_UNVERIFIED" do
    Client.install(runtime_code: "0x", admitted_safe?: false, owners: [], threshold: nil)
    assert {:ok, eoa} = Autolaunch.observe_treasury_security(@safe, %{}, actor: %System{})
    assert {eoa.classification, eoa.verification_state} == {:eoa, :unverified}

    Client.install(
      runtime_code: "0x6001",
      runtime_identity: "0x" <> String.duplicate("55", 32),
      admitted_safe?: false,
      owners: [],
      threshold: nil
    )

    assert {:ok, unknown} =
             Autolaunch.observe_treasury_security(@safe, %{}, actor: %System{})

    assert {unknown.classification, unknown.verification_state} ==
             {:unknown_contract, :unverified}
  end

  test "CLASSIFICATION_PRECEDENCE_IS_CLOSED_AND_NEVER_GUESSES_FROM_SAFE_SHAPE" do
    cases = [
      {[runtime_code: "0xef0100" <> String.duplicate("11", 20)], :delegated_eoa},
      {[
         runtime_code: "0xef0100" <> String.duplicate("11", 19),
         admitted_safe?: false
       ], :unknown_contract},
      {[admitted_safe?: true, owners: [hd(owners())], threshold: 1], :safe_1_of_1},
      {[admitted_safe?: false, admitted_split?: true, owners: [], threshold: nil], :split},
      {[admitted_safe?: false, admitted_split?: false, owners: [], threshold: nil],
       :unknown_contract}
    ]

    for {overrides, classification} <- cases do
      Client.install(overrides)
      assert {:ok, report} = Autolaunch.observe_treasury_security(@safe, %{}, actor: %System{})
      assert report.classification == classification
      assert report.verification_state == :unverified
    end
  end

  test "EVERY_SAFE_CONFIGURATION_DEVIATION_STAYS_HIGH_RISK_AND_UNVERIFIED" do
    cases = [
      {[owners: Enum.take(owners(), 2)], "safe_owner_count"},
      {[owners: [hd(owners()), hd(owners()), List.last(owners())]], "safe_duplicate_owners"},
      {[threshold: 1], "safe_threshold"},
      {[modules: [hd(owners())]], "safe_modules_enabled"},
      {[guard: hd(owners())], "safe_guard_enabled"},
      {[fallback_admitted?: false], "safe_fallback_unadmitted"}
    ]

    for {overrides, reason} <- cases do
      report = Client.seed_verified!(@safe, overrides)
      assert report.verification_state == :unverified
      assert report.verification_reason == reason
    end
  end

  test "ALL_THREE_HISTORICAL_PROOFS_ARE_REQUIRED" do
    Client.install()

    for {evidence, reason} <- [
          {%{}, "usdc_evidence_missing"},
          {%{usdc: tx_hash("11")}, "regent_evidence_missing"},
          {%{usdc: tx_hash("11"), regent: tx_hash("22")}, "outbound_evidence_missing"}
        ] do
      assert {:ok, report} =
               Autolaunch.observe_treasury_security(@safe, evidence, actor: %System{})

      assert report.verification_state == :unverified
      assert report.verification_reason == reason
    end
  end

  test "REVALIDATION_REJECTS_REORGS_AND_ACCEPTS_A_NEWER_IDENTICAL_SECURITY_STATE" do
    verified = Client.seed_verified!(@safe)

    Client.install(canonical?: false)

    assert {:error, :treasury_source_reorged} =
             AshPlatform.Autolaunch.TreasurySecurity.revalidate_bound(verified)

    Client.install(
      block_number: 30_000_001,
      block_hash: tx_hash("ef"),
      canonical_hashes: [verified.source_block_hash, tx_hash("ef")]
    )

    assert {:ok, newer} =
             AshPlatform.Autolaunch.TreasurySecurity.revalidate_bound(verified)

    refute newer.id == verified.id
    assert newer.configuration_fingerprint == verified.configuration_fingerprint
    assert newer.verification_state == :verified
  end

  test "CONFIGURATION_DRIFT_CREATES_AN_IMMUTABLE_DOWNGRADE" do
    verified = Client.seed_verified!(@safe)

    Client.install(
      block_number: 30_000_001,
      block_hash: "0x" <> String.duplicate("ef", 32),
      threshold: 1
    )

    assert {:ok, changed} =
             Autolaunch.observe_treasury_security(@safe, %{}, actor: %System{})

    assert changed.downgrade_state == :downgraded
    assert changed.prior_verified_fingerprint == verified.configuration_fingerprint
    assert verified.verification_state == :verified
  end

  defp owners do
    [
      "0x1111111111111111111111111111111111111111",
      "0x2222222222222222222222222222222222222222",
      "0x3333333333333333333333333333333333333333"
    ]
  end

  defp tx_hash(byte), do: "0x" <> String.duplicate(byte, 32)
end
