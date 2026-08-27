defmodule AshPlatform.Autolaunch.TreasurySecurityReportTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Autolaunch
  alias AshPlatform.Autolaunch.TreasurySecurityReport
  alias AshPlatform.TestAutolaunchTreasuryChainClient, as: Client

  test "REPORT_CREATION_IS_SYSTEM_ONLY_AND_NO_GENERIC_MUTATION_EXISTS" do
    report = Client.seed_verified!("0x9999999999999999999999999999999999999999")

    attrs = Map.take(report, TreasurySecurityReport.__schema__(:fields))

    assert {:error, _forbidden} =
             TreasurySecurityReport
             |> Ash.Changeset.for_create(:record_observation, attrs,
               domain: Autolaunch,
               actor: %Human{human_account_id: 1}
             )
             |> Ash.create(domain: Autolaunch, actor: %Human{human_account_id: 1})

    assert Enum.map(Ash.Resource.Info.actions(TreasurySecurityReport), & &1.type) |> Enum.sort() ==
             [:create, :read, :read, :read]

    assert {:ok, stored} = Autolaunch.get_treasury_security_report(report.id, actor: nil)
    assert stored.id == report.id

    Application.delete_env(:ash_platform, :autolaunch_treasury_chain_client)
    Application.delete_env(:ash_platform, :test_autolaunch_treasury_observation)
  end

  test "EVERY_REPORT_ASSOCIATION_PINS_THE_SAME_IMMUTABLE_TREASURY_ADDRESS" do
    report = Client.seed_verified!("0x9999999999999999999999999999999999999999")
    attrs = %{treasury_security_report_id: report.id}

    auction =
      Autolaunch.import_auction!("Pinned treasury", nil, false, :created, nil, attrs,
        actor: %System{}
      )

    assert auction.treasury_address == report.address

    token =
      Autolaunch.import_token!(
        auction.id,
        "Pinned token",
        "PIN",
        nil,
        DateTime.utc_now(),
        nil,
        attrs,
        actor: %System{}
      )

    assert token.treasury_address == report.address

    launch =
      Autolaunch.import_launch!(
        "launch:pinned-treasury",
        "ready",
        "reviewed",
        "agent:pinned",
        nil,
        "Pinned token",
        "PIN",
        8453,
        auction.id,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        attrs,
        actor: %System{}
      )

    assert launch.treasury_address == report.address

    subject =
      Autolaunch.import_subject!(
        "subject:pinned-treasury",
        "agent",
        8453,
        nil,
        nil,
        nil,
        report.address,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        attrs,
        actor: %System{}
      )

    assert subject.treasury_address == report.address

    other = Client.seed_verified!("0x8888888888888888888888888888888888888888")

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.set_auction_treasury_security_report(auction, other.id, actor: %System{})
  end

  test "TOKEN_AND_LAUNCH_JOB_PROVENANCE_COMES_ONLY_FROM_THE_REFERENCED_AUCTION" do
    report_a = Client.seed_verified!("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    report_b = Client.seed_verified!("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")

    auction_a =
      Autolaunch.import_auction!(
        "Auction A",
        nil,
        false,
        :created,
        nil,
        %{
          treasury_security_report_id: report_a.id
        },
        actor: %System{}
      )

    auction_b =
      Autolaunch.import_auction!(
        "Auction B",
        nil,
        false,
        :created,
        nil,
        %{
          treasury_security_report_id: report_b.id
        },
        actor: %System{}
      )

    mismatched = %{treasury_security_report_id: report_a.id}

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.import_token(
               auction_b.id,
               "Wrong report token",
               "WRONG",
               nil,
               DateTime.utc_now(),
               nil,
               mismatched,
               actor: %System{}
             )

    assert {:error, %Ash.Error.Invalid{}} =
             import_launch("launch:wrong-report", auction_b.id, mismatched)

    subject_a =
      Autolaunch.import_subject!(
        "subject:auction-a",
        "agent",
        8453,
        nil,
        nil,
        nil,
        report_a.address,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        mismatched,
        actor: %System{}
      )

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.import_subject_token(
               auction_b.id,
               subject_a.subject_id,
               "Wrong subject token",
               "WSUB",
               nil,
               DateTime.utc_now(),
               nil,
               %{},
               actor: %System{}
             )

    assert {:ok, token} =
             Autolaunch.import_token(
               auction_b.id,
               "Derived report token",
               "RIGHT",
               nil,
               DateTime.utc_now(),
               nil,
               %{},
               actor: %System{}
             )

    assert token.treasury_security_report_id == report_b.id
    assert token.treasury_address == report_b.address

    assert {:ok, launch} = import_launch("launch:derived-report", auction_b.id, %{})
    assert launch.treasury_security_report_id == report_b.id
    assert launch.treasury_address == report_b.address
    refute auction_a.id == auction_b.id
  end

  defp import_launch(job_id, auction_id, attrs) do
    Autolaunch.import_launch(
      job_id,
      "ready",
      "reviewed",
      "agent:provenance",
      nil,
      "Provenance token",
      "PROV",
      8453,
      auction_id,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      nil,
      attrs,
      actor: %System{}
    )
  end
end
