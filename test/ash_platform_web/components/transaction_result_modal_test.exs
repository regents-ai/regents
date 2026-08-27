defmodule AshPlatformWeb.Components.TransactionResultModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AshPlatformWeb.Components.TransactionResultModal, as: Modal

  @hash "0x" <> String.duplicate("ab", 32)

  defp fields(overrides \\ %{}) do
    Map.merge(
      %{
        status: :confirmed,
        action_id: "abc123",
        step: :action,
        hash: @hash,
        label: "Stake REGENT",
        message: Modal.confirmed_copy()
      },
      overrides
    )
  end

  # R2: the operation, its step, the classification and the exact hash. Nothing
  # else, so the same terminal transition always names the same result.
  test "R2_RESULT_IDENTITY: the id is the operation, step, classification and exact hash" do
    assert Modal.result(fields()).id == "abc123:action:confirmed:#{@hash}"
    assert Modal.result(fields()).id == Modal.result(fields()).id

    refute Modal.result(fields(%{step: :approval})).id == Modal.result(fields()).id
    refute Modal.result(fields(%{status: :reverted})).id == Modal.result(fields()).id

    other = "0x" <> String.duplicate("cd", 32)
    refute Modal.result(fields(%{hash: other})).id == Modal.result(fields()).id
  end

  # R3: the browser never supplies transaction truth, so a hash that is not an
  # exact transaction hash is not a result at all.
  test "R3_NO_INVENTED_TRANSACTION_TRUTH: a malformed or absent hash produces no result" do
    for hash <- [nil, "", "0xnot-a-hash", "0x" <> String.duplicate("ab", 31), @hash <> "\n"] do
      refute Modal.result(fields(%{hash: hash}))
    end
  end

  test "R3_EXACT_BASESCAN_LINK: only an exact transaction hash becomes a Base explorer link" do
    assert Modal.explorer_url(@hash) == "https://basescan.org/tx/#{@hash}"

    for hash <- [nil, "", "0xnot-a-hash", @hash <> "0"] do
      refute Modal.explorer_url(hash)
    end
  end

  test "R3_CLOSED_RESULT_CONTENT: each classification carries its own title and the producer's copy" do
    confirmed = Modal.result(fields())
    assert confirmed.title == "Transaction confirmed"
    assert confirmed.message == "Confirmed on Base."
    assert confirmed.label == "Stake REGENT"
    assert confirmed.transaction_hash == @hash

    assert Modal.result(fields(%{status: :reverted})).title == "Transaction reverted"
    assert Modal.result(fields(%{status: :unverified})).title == "Transaction not verified"
  end

  # R4: one portal source with a stable id, teleported to the body, so no shell
  # scroller, stacking context or mobile `inert` boundary can trap the dialog.
  test "R4_PORTAL_SOURCE_IS_STABLE_AND_TARGETS_THE_BODY" do
    html = render_component(&Modal.transaction_result/1, result: Modal.result(fields()))

    assert html =~ ~s(<template id="transaction-result-portal" data-phx-portal="body">)
    assert html =~ ~s(id="transaction-result-dialog")
    assert html =~ ~s(phx-hook="TransactionResultModal")
    refute html =~ ~s(phx-update="ignore")
  end

  test "R4_SERVER_OWNS_THE_CONTENT: the rendered dialog names the current result and its controls" do
    html = render_component(&Modal.transaction_result/1, result: Modal.result(fields()))

    assert html =~ ~s(data-result-id="abc123:action:confirmed:#{@hash}")
    assert html =~ "Transaction confirmed"
    assert html =~ "Stake REGENT"
    assert html =~ "Confirmed on Base."
    assert html =~ ~s(href="https://basescan.org/tx/#{@hash}")
    assert html =~ "View on BaseScan"
    assert html =~ "data-transaction-result-close"
  end

  test "R4_EMPTY_QUEUE_LEAVES_NO_RESULT: with nothing queued the dialog names no result" do
    html = render_component(&Modal.transaction_result/1, result: nil)

    assert html =~ ~s(id="transaction-result-dialog")
    refute html =~ "data-result-id"
    refute html =~ "basescan.org"
    refute html =~ "View on BaseScan"
  end
end
