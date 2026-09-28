defmodule Regents.Formation.RegentIdentityTest do
  use RegentsWeb.ConnCase, async: false

  alias Regents.Accounts
  alias Regents.Actors.{Human, System}
  alias Regents.Formation

  test "a human account cannot own two Regents" do
    account =
      Accounts.register_verified!(
        "did:privy:u3-unique-owner",
        "0x2222222222222222222222222222222222222222",
        ["0x2222222222222222222222222222222222222222"],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("first-regent", "First Regent", actor: actor)

    assert {:error, _error} =
             Formation.form_regent("second-regent", "Second Regent", actor: actor)
  end

  test "public lookup returns only the canonical Regent record" do
    account =
      Accounts.register_verified!(
        "did:privy:u3-public-read",
        "0x3333333333333333333333333333333333333333",
        ["0x3333333333333333333333333333333333333333"],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("public-regent", "Public Regent", actor: actor)

    assert {:ok, %{slug: "public-regent", display_name: "Public Regent"}} =
             Formation.get_public_regent("public-regent")

    assert {:ok, nil} = Formation.get_public_regent("missing-regent")
  end
end
