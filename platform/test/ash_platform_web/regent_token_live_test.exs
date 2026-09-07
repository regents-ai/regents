defmodule AshPlatformWeb.RegentTokenLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatformWeb.RegentTokenContent

  # The page is public editorial content: it needs no wallet, no sign-in and no
  # staking reading, so it renders whole even when the shared snapshot is gone.
  test "renders the token page complete for an anonymous visitor without a staking reading",
       %{conn: conn} do
    SnapshotCache.clear()
    on_exit(&SnapshotCache.clear/0)

    {:ok, view, html} = live(conn, "/regent")

    assert has_element?(view, "#regent-token h1", "$REGENT")
    assert html =~ "REGENT · Base"
    assert html =~ RegentTokenContent.token().address
    assert html =~ "100 billion REGENT"
    assert has_element?(view, ~s(a[href="#{RegentTokenContent.sources().token_blockscout}"]))
    assert has_element?(view, ~s(a[href="#{RegentTokenContent.sources().token_basescan}"]))
    assert has_element?(view, ~s(a[href="#{RegentTokenContent.sources().holders}"]))
    refute html =~ "Sign in"
    refute html =~ "Unavailable right now"
  end

  test "allocation, release schedule and holders are stated with their exact boundaries",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/regent")

    for share <- RegentTokenContent.allocation() do
      assert has_element?(view, ".regent-token-legend li", "#{share.percent}%")
      assert has_element?(view, ".regent-token-legend li", share.label)
    end

    # The vault boundaries appear to the second, as approved.
    assert html =~ "6 Nov 2025, 16:01:07 UTC"
    assert html =~ "6 Nov 2026, 16:01:07 UTC"
    assert html =~ "6 Nov 2027, 16:01:07 UTC"
    assert html =~ "5 Nov 2028, 16:01:07 UTC"
    assert has_element?(view, ~s(.regent-token-timeline time[datetime="2026-11-06T16:01:07Z"]))
    assert html =~ "Eligibility is not a sale or circulation."

    for holder <- RegentTokenContent.holders() do
      assert has_element?(view, ~s(.regent-token-table th[scope="row"]), holder.label)
      assert html =~ holder.address
    end

    # Exact balances stay readable; the shortened figure is what is shown.
    assert html =~ "14,796,504,503.504863237545574501"
    assert html =~ "14.79 billion"
    assert html =~ "14.7%"
    assert html =~ "12.6%"
    assert html =~ RegentTokenContent.written(RegentTokenContent.reviewed_at())
  end

  test "deeper mechanics, signers and sources are in the HTML behind native disclosures",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/regent")

    assert has_element?(view, "details.regent-token-details summary", "Original allocation plan")
    assert has_element?(view, "details.regent-token-details summary", "How the vault releases")
    assert has_element?(view, "details.regent-token-details summary", "Signer addresses")

    assert has_element?(
             view,
             "details.regent-token-details summary",
             "How staking rewards are worked out"
           )

    assert has_element?(view, "details.regent-token-details summary", "Contracts and sources")
    refute has_element?(view, "details.regent-token-details[open]")

    for owner <- RegentTokenContent.treasury().owners, do: assert(html =~ owner)
    for bucket <- RegentTokenContent.original_policy().labs, do: assert(html =~ bucket)
    assert html =~ RegentTokenContent.vault().address
    assert html =~ RegentTokenContent.staking().address
    assert html =~ RegentTokenContent.redemption().address
    assert html =~ RegentTokenContent.launch().transaction
    assert html =~ "capped at 20% a year"
    assert html =~ "2 of 3 when checked"
    assert has_element?(view, ~s(a[href="/stake"]), "Stake")
    assert has_element?(view, ~s(a[href="/redeem"]), "Redeem")
  end

  test "percent_of_genesis never rounds up" do
    assert RegentTokenContent.percent_of_genesis("40000000000") == "40"
    assert RegentTokenContent.percent_of_genesis("14796504503.504863237545574501") == "14.7"
    assert RegentTokenContent.percent_of_genesis("2859857607.163533118952566772") == "2.8"
    assert RegentTokenContent.percent_of_genesis("99999999999") == "99.9"
  end

  test "release_timeline is cumulative eligibility at the approved boundaries" do
    assert [funded, unlock, midway, vested] = RegentTokenContent.release_timeline()
    assert funded.at == ~U[2025-11-06 16:01:07Z] and funded.eligible_tokens == "0"
    assert unlock.at == ~U[2026-11-06 16:01:07Z] and unlock.eligible_tokens == "0"
    assert midway.at == ~U[2027-11-06 16:01:07Z] and midway.eligible_tokens == "20000000000"
    assert vested.at == ~U[2028-11-05 16:01:07Z] and vested.eligible_tokens == "40000000000"
  end
end
