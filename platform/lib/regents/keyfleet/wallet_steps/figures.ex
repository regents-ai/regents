defmodule Regents.Keyfleet.WalletSteps.Figures do
  @moduledoc """
  The figures a group of wallet buttons shows, read for a visitor exactly as
  `Regents.Keyfleet.WalletSteps.Build` reads them for a signer:
  `%{figures: figures, problem: problem}`. Nothing is built to send.
  """
  use Ash.Resource.Actions.Implementation

  alias Regents.Keyfleet.WalletSteps.Build

  @impl true
  def run(input, _opts, _context) do
    with {:ok, _request, built} <- Build.build(input.arguments, nil),
         do: {:ok, Map.take(built, [:figures, :problem])}
  end
end
