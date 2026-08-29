import type {Hook} from "../hook_composition"
import {
  activeEthereumWallet,
  type SelectedWallet,
} from "../wallet_actions/connected_wallet"
import {
  sendLabPositionStep,
  sendableLabPositionStep,
  userRejected,
  type LabPositionOperation,
} from "../wallet_actions/autolaunch_lab_position"

type LabPositionHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEventTo(target: HTMLElement, event: string, payload: unknown): void
  publishActiveWallet?: () => void
}

export const AutolaunchLabPosition: Hook = {
  mounted(this: LabPositionHook) {
    let operation: LabPositionOperation | null = null
    const push = (event: string, payload: unknown) => this.pushEventTo(this.el, event, payload)

    this.publishActiveWallet = () =>
      push("lab_position_active_wallet", {address: activeEthereumWallet()?.address ?? null})
    window.addEventListener("ash:wallet-state", this.publishActiveWallet)
    this.publishActiveWallet()

    this.handleEvent("autolaunch-lab-position:operation", payload => {
      operation = payload as LabPositionOperation
    })
    this.handleEvent("autolaunch-lab-position:cleared", () => {
      operation = null
    })

    this.el.addEventListener("click", async event => {
      const target = (event.target as HTMLElement | null) ?? null
      if (target?.closest("[data-lab-position-connect]")) {
        window.dispatchEvent(new CustomEvent("ash:wallet-connect"))
        return
      }

      const prepare = target?.closest<HTMLElement>("[data-lab-position-prepare]")
      if (prepare?.dataset.labPositionPrepare) {
        push("prepare_lab_position", {
          address: activeEthereumWallet()?.address ?? null,
          kind: prepare.dataset.labPositionPrepare,
        })
        return
      }

      const send = target?.closest<HTMLElement>("[data-lab-position-send]")
      const actionId = send?.dataset.labPositionSend
      const signer = send?.dataset.labPositionSigner
      if (actionId && signer) {
        if (await activeWalletForSigner(signer)) {
          push("sign_lab_position_step", {"action-id": actionId})
        } else {
          push("lab_position_dispatch_not_started", {action_id: actionId})
        }
        return
      }

      const verify = target?.closest<HTMLElement>("[data-lab-position-verify]")
      if (verify?.dataset.labPositionVerify) {
        push("lab_position_verify", {"action-id": verify.dataset.labPositionVerify})
        return
      }

      const cancel = target?.closest<HTMLElement>("[data-lab-position-cancel]")
      if (cancel?.dataset.labPositionCancel) {
        push("cancel_lab_position", {"action-id": cancel.dataset.labPositionCancel})
        return
      }

      const startNew = target?.closest<HTMLElement>("[data-lab-position-start-new]")
      if (startNew?.dataset.labPositionStartNew) {
        push("start_new_lab_position", {"action-id": startNew.dataset.labPositionStartNew})
      }
    })

    this.handleEvent("autolaunch-lab-position:send", async payload => {
      const {action_id: actionId, step: stepName} = payload as {
        action_id: string
        step: string
      }
      const held = operation
      if (!held) return

      let sendStarted = false
      const notStarted = () =>
        push("lab_position_dispatch_not_started", {action_id: actionId})

      try {
        const step = sendableLabPositionStep(held, actionId, stepName)
        if (!(await activeWalletForSigner(held.signer))) {
          notStarted()
          return
        }

        const hash = await sendLabPositionStep(
          held,
          step,
          activeEthereumWallet,
          () => (sendStarted = true),
        )
        const reported = {action_id: actionId, step: step.step, transaction_hash: hash}
        push("lab_position_submitted", reported)
      } catch (error) {
        if (!sendStarted) {
          notStarted()
          return
        }
        if (userRejected(error)) {
          push("lab_position_rejected", {action_id: actionId, code: 4001})
        }
      }
    })
  },

  destroyed(this: LabPositionHook) {
    if (this.publishActiveWallet) {
      window.removeEventListener("ash:wallet-state", this.publishActiveWallet)
    }
  },
}

async function activeWalletForSigner(expectedSigner: string): Promise<SelectedWallet | null> {
  const active = activeEthereumWallet()
  if (!active || !sameHex(active.address, expectedSigner)) return null

  const accounts = await active.provider.request({method: "eth_accounts"}).catch(() => null)
  const [account] = Array.isArray(accounts) ? accounts : []
  return typeof account === "string" && sameHex(account, expectedSigner) ? active : null
}

function sameHex(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase()
}
