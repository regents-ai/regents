defmodule RegentsWeb.Patchbay.Plugs.AgentPaymentAdmission do
  @moduledoc "New settlement attempts require the verified agent's current pairing."
  @behaviour Plug
  alias RegentsWeb.Patchbay.Plugs.PairedAgent

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case PairedAgent.attach_verified_wallet(conn, conn.assigns.verified_agent_wallet) do
      {:ok, conn} -> conn
      {:error, failure} -> PairedAgent.deny(conn, failure)
    end
  end
end
