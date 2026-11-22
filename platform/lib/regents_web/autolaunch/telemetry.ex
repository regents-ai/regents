defmodule RegentsWeb.Autolaunch.Telemetry do
  @moduledoc false

  def wallet_failed(action, reason) do
    :telemetry.execute([:autolaunch, :wallet, :failed], %{count: 1}, %{
      action: action,
      reason: reason
    })
  end
end
