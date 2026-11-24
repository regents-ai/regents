defmodule RegentsWeb.Chain.ReceiptCheck do
  @moduledoc "Starts a LiveView receipt read for one submitted wallet step."

  import Phoenix.LiveView, only: [start_async: 3]

  alias RegentChain.Outcome

  @recheck_ms 2_000

  def start(socket, client, %{hash: hash, reads: reads, review: review, step: step}) do
    start_async(socket, {:onchain_step, hash}, fn ->
      if reads > 0, do: Process.sleep(@recheck_ms)
      Outcome.of(client, review, step, hash)
    end)
  end
end
