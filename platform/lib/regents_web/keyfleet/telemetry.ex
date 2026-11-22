defmodule RegentsWeb.Keyfleet.Telemetry do
  @moduledoc """
  The events Keyfleet's pages report, as `:telemetry` events; which of them
  the site exports as metrics is the site's own list (`RegentsWeb.Telemetry`).
  `[:regents, :keyfleet_wallet, :failure]` counts each press the browser
  reported as not sent or not confirmed, or the server refused to build steps
  for (`wallet_failed/2`).
  """

  # The reasons the wallet hook reports (`Failure` in send_step.ts), and
  # `blocked`, a press the server refused because the chain's state makes its
  # step certain to fail. Only these are counted, so a label never holds
  # whatever a browser chose to send.
  @wallet_failures ~w(step_unknown blocked wallet_unavailable switch_declined network_mismatch wallet_declined insufficient_funds send_unconfirmed sign_unconfirmed)

  @doc """
  Counts one press the browser reported as not sent or not confirmed, or the
  server refused to hand steps over for (`step_unknown`, or `blocked` when
  the chain's state makes the step certain to fail), for the wallet flow
  `flow`. Any other reason is not counted.
  """
  def wallet_failed(flow, reason) when reason in @wallet_failures do
    :telemetry.execute([:regents, :keyfleet_wallet, :failure], %{count: 1}, %{
      flow: flow,
      reason: reason
    })
  end

  def wallet_failed(_flow, _reason), do: :ok
end
