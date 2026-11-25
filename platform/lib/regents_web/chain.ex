defmodule RegentsWeb.Chain do
  @moduledoc """
  The shared wallet steps, on-chain button, receipts and token display.
  """
  use Boundary,
    deps: [RegentsWeb],
    exports: [
      OnchainButton,
      OnchainSteps,
      ReadBudget,
      ReceiptCheck,
      SubmittedTransactions,
      TokenDisplay,
      TransactionReceipt
    ]
end
