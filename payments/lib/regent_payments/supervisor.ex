defmodule RegentPayments.Supervisor do
  @moduledoc """
  The two processes a site starts for payments, beside its repository: the
  HTTP pool the facilitator client uses and the facilitator client itself,
  configured under `config :regent_payments, RegentPayments.Facilitator`.

  The client never retries on its own. A timed-out settlement may already
  have moved value, so a retry is always a decision, never a reflex.
  """

  use Supervisor

  @doc false
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {Finch,
       name: RegentPayments.Finch, pools: %{default: X402.Facilitator.HTTP.secure_pool_opts()}},
      {X402.Facilitator,
       otp_app: :regent_payments,
       name: RegentPayments.Facilitator,
       finch: RegentPayments.Finch,
       max_retries: 0}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
