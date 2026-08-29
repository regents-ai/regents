import {getAddress, type Address, type Hash, type Hex} from "viem"

import {
  labNetwork,
  sendLabTransaction,
  type AutolaunchLabAnchor,
  type AutolaunchLabBinding,
  type WalletResolver,
} from "./autolaunch_network"

export type LabPositionStep = {
  step: string
  to: Address
  data: Hex
}

export type LabPositionOperation = {
  action_id: string
  signer: Address
  chain_id: number
  lab: AutolaunchLabBinding | null
  lab_anchor: AutolaunchLabAnchor | null
  terminal: boolean
  steps: LabPositionStep[]
}

export function sendableLabPositionStep(
  operation: LabPositionOperation,
  actionId: string,
  stepName: string,
): LabPositionStep {
  if (operation.action_id !== actionId) throw new Error("This is a different lab position.")
  if (operation.terminal) throw new Error("This lab position action has already finished.")
  if (!labNetwork(operation)) throw new Error("A lab position cannot be sent to Base.")

  const step = operation.steps.find(candidate => candidate.step === stepName)
  if (!step || step.step.length === 0) {
    throw new Error("This step is not part of the reviewed lab position action.")
  }

  getAddress(step.to)
  if (!/^0x[0-9a-f]+$/.test(step.data)) throw new Error("The reviewed transaction changed.")
  return step
}

export function sendLabPositionStep(
  operation: LabPositionOperation,
  step: LabPositionStep,
  resolveWallet: WalletResolver,
  onSendStarted: () => void,
): Promise<Hash> {
  return sendLabTransaction(operation, step, resolveWallet, onSendStarted)
}

export function userRejected(error: unknown): boolean {
  const seen = new Set<unknown>()
  let current = error

  while (current && typeof current === "object" && !seen.has(current)) {
    seen.add(current)
    if ((current as {code?: unknown}).code === 4001) return true
    current = (current as {cause?: unknown}).cause
  }

  return false
}
