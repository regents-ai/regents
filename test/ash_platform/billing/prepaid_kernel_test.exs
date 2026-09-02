defmodule AshPlatform.Billing.PrepaidKernelTest do
  use AshPlatformWeb.ConnCase, async: false

  import AshPlatform.SandboxRace, only: [race_each: 1]

  alias AshPlatform.{Accounts, Billing}
  alias AshPlatform.Actors.{Human, System}

  test "provider funding is system-only, positive, exact, and idempotent" do
    {account, owner} = owner_fixture("funding")

    assert {:error, _} =
             Billing.record_provider_funding(account.id, "payment-1", 500, actor: owner)

    first =
      Billing.record_provider_funding!(account.id, "payment-1", 500, actor: %System{})

    retry =
      Billing.record_provider_funding!(account.id, "payment-1", 500, actor: %System{})

    assert retry.id == first.id

    assert {:error, _} =
             Billing.record_provider_funding(account.id, "payment-1", 501, actor: %System{})

    assert %{funded_cents: 500, available_cents: 500, reserved_cents: 0, consumed_cents: 0} =
             Billing.credit_summary!(account.id, actor: owner)
  end

  test "a provider reference and reservation operation key are globally bound" do
    {first_account, first_owner} = funded_owner_fixture("global-first", 500)
    {second_account, second_owner} = owner_fixture("global-second")

    assert {:error, _} =
             Billing.record_provider_funding(
               second_account.id,
               "funding-global-first",
               500,
               actor: %System{}
             )

    first = Billing.reserve_spend!(first_account.id, "shared-operation", 200, actor: first_owner)
    assert first.amount_cents == 200

    Billing.record_provider_funding!(
      second_account.id,
      "funding-global-second",
      500,
      actor: %System{}
    )

    assert {:error, _} =
             Billing.reserve_spend(second_account.id, "shared-operation", 200,
               actor: second_owner
             )
  end

  test "only the owner can read or reserve an account" do
    {account, owner} = funded_owner_fixture("ownership", 500)
    {_other_account, other_owner} = owner_fixture("ownership-other")

    assert {:error, _} = Billing.credit_summary(account.id, actor: other_owner)
    assert {:error, _} = Billing.reserve_spend(account.id, "not-yours", 100, actor: other_owner)

    assert %{available_cents: 500} = Billing.credit_summary!(account.id, actor: owner)
  end

  test "reservation retry is exact and cannot overspend" do
    {account, owner} = funded_owner_fixture("reserve", 500)

    first = Billing.reserve_spend!(account.id, "operation-1", 300, actor: owner)
    retry = Billing.reserve_spend!(account.id, "operation-1", 300, actor: owner)

    assert retry.id == first.id
    assert {:error, _} = Billing.reserve_spend(account.id, "operation-1", 301, actor: owner)
    assert {:error, _} = Billing.reserve_spend(account.id, "operation-2", 201, actor: owner)

    assert_balanced(account.id, owner, 500, 200, 300, 0)
  end

  test "partial and full settlement consume once and terminal reservations do not reopen" do
    {account, owner} = funded_owner_fixture("consume", 500)
    reservation = Billing.reserve_spend!(account.id, "usage-window", 300, actor: owner)

    partial =
      Billing.consume_reserved_spend!(
        account.id,
        reservation.id,
        "settlement-1",
        120,
        actor: owner
      )

    assert partial.status == :active
    assert partial.consumed_cents == 120

    retry =
      Billing.consume_reserved_spend!(
        account.id,
        reservation.id,
        "settlement-1",
        120,
        actor: owner
      )

    assert retry.consumed_cents == 120

    assert {:error, _} =
             Billing.consume_reserved_spend(
               account.id,
               reservation.id,
               "settlement-1",
               121,
               actor: owner
             )

    full =
      Billing.consume_reserved_spend!(
        account.id,
        reservation.id,
        "settlement-2",
        180,
        actor: owner
      )

    assert full.status == :consumed
    assert full.consumed_cents == 300

    assert {:error, _} =
             Billing.consume_reserved_spend(
               account.id,
               reservation.id,
               "settlement-3",
               1,
               actor: owner
             )

    assert {:error, _} = Billing.release_reservation(account.id, reservation.id, actor: owner)
    assert_balanced(account.id, owner, 500, 200, 0, 300)
  end

  test "release and expiry return only unconsumed credit and are idempotent" do
    {release_account, release_owner} = funded_owner_fixture("release", 500)

    release =
      Billing.reserve_spend!(release_account.id, "release-window", 300, actor: release_owner)

    Billing.consume_reserved_spend!(
      release_account.id,
      release.id,
      "release-partial",
      80,
      actor: release_owner
    )

    released = Billing.release_reservation!(release_account.id, release.id, actor: release_owner)

    released_retry =
      Billing.release_reservation!(release_account.id, release.id, actor: release_owner)

    assert released.status == :released
    assert released_retry.id == released.id

    assert {:error, _} =
             Billing.expire_reservation(release_account.id, release.id, actor: release_owner)

    assert_balanced(release_account.id, release_owner, 500, 420, 0, 80)

    {expire_account, expire_owner} = funded_owner_fixture("expire", 400)
    expiry = Billing.reserve_spend!(expire_account.id, "expiry-window", 250, actor: expire_owner)
    expired = Billing.expire_reservation!(expire_account.id, expiry.id, actor: expire_owner)
    expired_retry = Billing.expire_reservation!(expire_account.id, expiry.id, actor: expire_owner)
    assert expired.status == :expired
    assert expired_retry.id == expired.id
    assert_balanced(expire_account.id, expire_owner, 400, 400, 0, 0)
  end

  test "a different owner cannot settle, release, or expire a reservation" do
    {account, owner} = funded_owner_fixture("transition-owner", 500)
    {_other_account, other_owner} = owner_fixture("transition-other")
    reservation = Billing.reserve_spend!(account.id, "owner-window", 200, actor: owner)

    assert {:error, _} =
             Billing.consume_reserved_spend(
               account.id,
               reservation.id,
               "foreign-settlement",
               10,
               actor: other_owner
             )

    assert {:error, _} =
             Billing.release_reservation(account.id, reservation.id, actor: other_owner)

    assert {:error, _} =
             Billing.expire_reservation(account.id, reservation.id, actor: other_owner)

    assert_balanced(account.id, owner, 500, 300, 200, 0)
  end

  test "concurrent reservations cannot make available credit negative" do
    {account, owner} = funded_owner_fixture("concurrency", 500)

    results =
      race_each(
        for key <- ["concurrent-a", "concurrent-b"] do
          fn -> Billing.reserve_spend(account.id, key, 400, actor: owner) end
        end
      )

    assert 1 == Enum.count(results, &match?({:ok, _}, &1))
    assert 1 == Enum.count(results, &match?({:error, _}, &1))
    assert_balanced(account.id, owner, 500, 100, 400, 0)
  end

  defp funded_owner_fixture(suffix, amount_cents) do
    {account, owner} = owner_fixture(suffix)

    Billing.record_provider_funding!(
      account.id,
      "funding-#{suffix}",
      amount_cents,
      actor: %System{}
    )

    {account, owner}
  end

  defp owner_fixture(suffix) do
    account =
      Accounts.register_verified!(
        "did:privy:billing:#{suffix}:#{:erlang.unique_integer([:positive])}",
        nil,
        [],
        actor: %System{}
      )

    {account, %Human{human_account_id: account.id}}
  end

  defp assert_balanced(account_id, owner, funded, available, reserved, consumed) do
    summary = Billing.credit_summary!(account_id, actor: owner)
    assert summary.funded_cents == funded
    assert summary.available_cents == available
    assert summary.reserved_cents == reserved
    assert summary.consumed_cents == consumed
    assert funded == available + reserved + consumed
    assert Enum.all?([available, reserved, consumed], &(&1 >= 0))
  end
end
