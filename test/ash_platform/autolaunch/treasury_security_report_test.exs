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
end
