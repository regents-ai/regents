import {encodeFunctionData, getAddress, parseAbi, type Hash, type Hex} from "viem"
import {afterEach, describe, expect, it, vi} from "vitest"

import ingressAbi from "../../contracts/abi/revenue-ingress-account.json"
import paymentLinkAbi from "../../contracts/abi/payment-link-factory.json"
import splitterAbi from "../../contracts/abi/revenue-share-splitter-v2.json"
import {
  assertSubjectPaymentEnvelope,
  executePreparedSubjectPaymentAction,
  type PreparedSubjectPaymentAction,
  type SubjectPaymentAction,
  type SubjectPaymentClients,
} from "../js/wallet_actions/autolaunch_subject_payments"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const token = getAddress("0x2222222222222222222222222222222222222222")
const splitter = getAddress("0x3333333333333333333333333333333333333333")
const ingress = getAddress("0x4444444444444444444444444444444444444444")
const factory = getAddress("0x5555555555555555555555555555555555555555")
const paymentLink = getAddress("0x6666666666666666666666666666666666666666")
const replacement = getAddress("0x7777777777777777777777777777777777777777")
const subjectId = `0x${"53".repeat(32)}` as Hex
const salt = `0x${"ab".repeat(32)}` as Hex
const approvalHash = `0x${"cd".repeat(32)}` as Hash
const actionHash = `0x${"ef".repeat(32)}` as Hash
const approvalAbi = parseAbi(["function approve(address spender,uint256 amount)"])

function envelope(action: SubjectPaymentAction): PreparedSubjectPaymentAction {
  const common = {
    action_id: `action-${action}`,
    idempotency_key: `action-${action}`,
    confirmation_token: "signed",
    chain_id: 8453 as const,
    value: "0" as const,
    expected_signer: wallet,
    prepared_at: new Date(Date.now() - 1000).toISOString(),
    expires_at: new Date(Date.now() + 120_000).toISOString(),
    risk_copy: "Review this subject action.",
  }

  if (action === "create_payment_link" || action === "create_canonical_payment_link") {
    const canonical = action === "create_canonical_payment_link"
    const data = encodeFunctionData({
      abi: paymentLinkAbi,
      functionName: canonical ? "createCanonicalPaymentLink" : "createPaymentLink",
      args: [subjectId, "Sponsor", salt],
    })

    return {
      ...common,
      resource: "autolaunch_payment_link",
      action,
      to: factory,
      data,
      approval: null,
      arguments: {subject_id: subjectId, factory, label: "Sponsor", canonical, salt},
    }
  }

  if (action === "set_payment_link_canonical") {
    const data = encodeFunctionData({
      abi: paymentLinkAbi,
      functionName: "setPaymentLinkCanonical",
      args: [paymentLink, true],
    })

    return {
      ...common,
      resource: "autolaunch_payment_link",
      action,
      to: factory,
      data,
      approval: null,
      arguments: {subject_id: subjectId, factory, receiver: paymentLink, canonical: true},
    }
  }

  if (action === "set_payment_link_receiver_state") {
    const data = encodeFunctionData({
      abi: paymentLinkAbi,
      functionName: "setPaymentLinkReceiverState",
      args: [paymentLink, false, replacement],
    })

    return {
      ...common,
      resource: "autolaunch_payment_link",
      action,
      to: factory,
      data,
      approval: null,
      arguments: {
        subject_id: subjectId,
        factory,
        receiver: paymentLink,
        active: false,
        replacement,
      },
    }
  }

  if (action === "sweep_usdc") {
    const data = encodeFunctionData({
      abi: ingressAbi,
      functionName: "sweepUSDC",
      args: [subjectId],
    })

    return {
      ...common,
      resource: "autolaunch_ingress",
      action,
      to: ingress,
      data,
      approval: null,
      arguments: {subject_id: subjectId, ingress_account: ingress, source_ref: subjectId},
    }
  }

  if (action === "stake") {
    const amount = "1250000000000000000"
    const data = encodeFunctionData({
      abi: splitterAbi,
      functionName: "stake",
      args: [BigInt(amount), wallet],
    })
    const approvalData = encodeFunctionData({
      abi: approvalAbi,
      functionName: "approve",
      args: [splitter, BigInt(amount)],
    })

    return {
      ...common,
      resource: "autolaunch_subject_staking",
      action,
      to: splitter,
      data,
      approval: {
        token,
        spender: splitter,
        amount,
        data: approvalData,
        mode: "exact",
      },
      arguments: {
        subject_id: subjectId,
        splitter,
        token,
        amount_atomic: amount,
        receiver: wallet,
      },
    }
  }

  if (action === "unstake") {
    const amount = "500000000000000000"
    const data = encodeFunctionData({
      abi: splitterAbi,
      functionName: "unstake",
      args: [BigInt(amount), wallet],
    })

    return {
      ...common,
      resource: "autolaunch_subject_staking",
      action,
      to: splitter,
      data,
      approval: null,
      arguments: {
        subject_id: subjectId,
        splitter,
        amount_atomic: amount,
        recipient: wallet,
      },
    }
  }

  const data = encodeFunctionData({
    abi: splitterAbi,
    functionName: "claimUSDC",
    args: [wallet],
  })

  return {
    ...common,
    resource: "autolaunch_subject_staking",
    action,
    to: splitter,
    data,
    approval: null,
    arguments: {subject_id: subjectId, splitter, recipient: wallet},
  }
}

function clients(overrides: Partial<SubjectPaymentClients> = {}): SubjectPaymentClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    send: vi.fn(async request => (request.to === token ? approvalHash : actionHash)),
    receipt: vi.fn(async () => ({status: "success" as const})),
    ...overrides,
  }
}

afterEach(() => vi.useRealTimers())

describe("Autolaunch subject payment wallet actions", () => {
  it("recomputes every admitted implementation call before signing", () => {
    for (const action of [
      "create_payment_link",
      "create_canonical_payment_link",
      "set_payment_link_canonical",
      "set_payment_link_receiver_state",
      "sweep_usdc",
      "stake",
      "unstake",
      "claim_usdc",
    ] satisfies SubjectPaymentAction[]) {
      expect(() => assertSubjectPaymentEnvelope(envelope(action))).not.toThrow()
    }
  })

  it("submits exact approval then stake and records each hash before receipt waiting", async () => {
    const boundary = clients()
    const submitted = vi.fn()

    await expect(
      executePreparedSubjectPaymentAction(
        envelope("stake"),
        {request: vi.fn()},
        boundary,
        {onSubmitted: submitted},
      ),
    ).resolves.toEqual({approvalHash, transactionHash: actionHash})

    expect(boundary.send).toHaveBeenNthCalledWith(1, {
      account: wallet,
      to: token,
      data: envelope("stake").approval?.data,
      value: 0n,
    })
    expect(boundary.send).toHaveBeenNthCalledWith(2, {
      account: wallet,
      to: splitter,
      data: envelope("stake").data,
      value: 0n,
    })
    expect(submitted).toHaveBeenNthCalledWith(1, "approval", approvalHash)
    expect(submitted).toHaveBeenNthCalledWith(2, "action", actionHash)
    expect(submitted.mock.invocationCallOrder[0]).toBeLessThan(
      (boundary.receipt as ReturnType<typeof vi.fn>).mock.invocationCallOrder[0],
    )
  })

  it("fails closed on signer, chain 1, identity drift, calldata drift, and approval drift", async () => {
    await expect(
      executePreparedSubjectPaymentAction(
        envelope("claim_usdc"),
        {request: vi.fn()},
        clients({addresses: vi.fn(async () => [replacement])}),
      ),
    ).rejects.toThrow("connected wallet")

    const base = envelope("stake")
    for (const changed of [
      {...base, chain_id: 1},
      {...base, to: replacement},
      {...base, data: "0xdeadbeef"},
      {...base, idempotency_key: "changed"},
      {...base, approval: {...base.approval!, amount: "2"}},
      {...base, arguments: {...base.arguments, splitter: replacement}},
      {
        ...envelope("create_payment_link"),
        arguments: {...envelope("create_payment_link").arguments, canonical: true},
      },
    ]) {
      expect(() =>
        assertSubjectPaymentEnvelope(
          changed as unknown as PreparedSubjectPaymentAction,
        ),
      ).toThrow()
    }
  })

  it("requires more than 60 seconds before opening either wallet request", async () => {
    vi.useFakeTimers()

    for (const remaining of [60_000, 59_999, 0]) {
      const boundary = clients()
      const prepared = {
        ...envelope("stake"),
        expires_at: new Date(Date.now() + remaining).toISOString(),
      }

      await expect(
        executePreparedSubjectPaymentAction(
          prepared,
          {request: vi.fn()},
          boundary,
        ),
      ).rejects.toThrow("Prepare it again")

      expect(boundary.chainId).not.toHaveBeenCalled()
      expect(boundary.send).not.toHaveBeenCalled()
    }
  })

  it("keeps submitted hashes when an approval or action receipt reverts", async () => {
    const approvalSubmitted = vi.fn()
    const approvalBoundary = clients({
      receipt: vi.fn(async () => ({status: "reverted" as const})),
    })

    await expect(
      executePreparedSubjectPaymentAction(
        envelope("stake"),
        {request: vi.fn()},
        approvalBoundary,
        {onSubmitted: approvalSubmitted},
      ),
    ).rejects.toThrow("approval reverted")

    expect(approvalSubmitted).toHaveBeenCalledWith("approval", approvalHash)

    const actionSubmitted = vi.fn()
    const actionBoundary = clients({
      receipt: vi
        .fn()
        .mockResolvedValueOnce({status: "success" as const})
        .mockResolvedValueOnce({status: "reverted" as const}),
    })

    await expect(
      executePreparedSubjectPaymentAction(
        envelope("stake"),
        {request: vi.fn()},
        actionBoundary,
        {onSubmitted: actionSubmitted},
      ),
    ).rejects.toThrow("subject transaction reverted")

    expect(actionSubmitted).toHaveBeenCalledWith("action", actionHash)
  })

})
