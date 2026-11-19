defmodule RegentsWeb.Chain do
  @moduledoc """
  The wallet steps, on-chain button, receipts and token display that Stake and Redeem
  pages share.
  """
  use Boundary,
    deps: [RegentsWeb],
    exports: [
      OnchainButton,
      OnchainSteps,
      ReadBudget,
      SubmittedTransactions,
      TokenDisplay,
      TransactionReceipt
    ]
end
