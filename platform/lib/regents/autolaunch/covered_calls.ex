defmodule Regents.Autolaunch.CoveredCalls do
  @moduledoc """
  Covered calls on Base stock tokens: a seller locks stock and lists calls on
  it; any person or agent buys them for a premium in USDC, or posts a standing
  bid with its premium escrowed that a seller sells into and is paid at once;
  during the 24 hours after the Friday expiry a holder may pay the strike for
  the stock. The contract is the record every page and agent reads. The site
  saves only each call that changed hands (`Sale`), with how far it has read
  each market's contract (`Cursor`), for Regent Points.

  Its two tables as autolaunch.sh keeps them; nothing here reads or writes
  them yet.
  """

  use Ash.Domain, otp_app: :regents

  resources do
    resource Regents.Autolaunch.CoveredCalls.Sale
    resource Regents.Autolaunch.CoveredCalls.Cursor
  end
end
