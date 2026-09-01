export type ResultDisplay = Readonly<{
  title: string
  message: string
  detail: string
  href: string | null
  tone: "success" | "error" | "pending"
}>

type ProgressView = {
  progress: HTMLElement
  progressTitle: HTMLElement
  progressCopy: HTMLElement
}

type ResultView = {
  dialog: HTMLDialogElement
  dialogTitle: HTMLElement
  text: HTMLElement
  detail: HTMLElement
  walletText: HTMLElement
  link: HTMLAnchorElement
}

export function setProgress(
  view: ProgressView,
  phase: string,
  title: string,
  copy: string,
): void {
  view.progress.hidden = false
  view.progress.dataset.phase = phase
  view.progressTitle.textContent = title
  view.progressCopy.textContent = copy
}

export function clearProgress(view: ProgressView): void {
  view.progress.hidden = true
  view.progress.dataset.phase = "idle"
  view.progressTitle.textContent = ""
  view.progressCopy.textContent = ""
}

export function renderResult(
  view: ResultView,
  display: ResultDisplay,
  signer: string,
): void {
  view.dialog.dataset.tone = display.tone
  view.dialogTitle.textContent = display.title
  view.text.textContent = display.message
  view.detail.textContent = display.detail
  view.walletText.textContent = shortWallet(signer)
  view.link.textContent = ""
  view.link.removeAttribute("href")
  view.link.hidden = true

  if (display.href) {
    view.link.textContent = "View on BaseScan"
    view.link.href = display.href
    view.link.target = "_blank"
    view.link.rel = "noopener noreferrer"
    view.link.hidden = false
  }
}

function shortWallet(wallet: string): string {
  return /^0x[0-9a-f]{40}$/i.test(wallet) ? `${wallet.slice(0, 6)}…${wallet.slice(-4)}` : "—"
}
