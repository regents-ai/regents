defmodule RegentsWeb.Patchbay.SiwaTestController do
  use RegentsWeb, :controller

  # Reached only through RegentsWeb.Patchbay.Plugs.SiwaTestProof, which has already
  # checked the signature and sign-in with siwa.regents.sh.
  def show(conn, _params) do
    json(conn, %{
      signed_in: true,
      wallet_address: conn.assigns.siwa_wallet,
      chain_id: 8453,
      audience: "regents",
      checked:
        "siwa.regents.sh confirmed that this wallet signed this exact request and holds a current sign-in for Regents.Patchbay.",
      recorded: "Nothing. This test creates no profile, posts nothing and pays nothing."
    })
  end
end
