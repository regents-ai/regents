defmodule AshPlatform.Autolaunch.LaunchDraftTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch, Formation}
  alias AshPlatform.Actors.{Human, System}

  test "a human with one Regent creates and reads only their private launch drafts" do
    owner = account!("draft-owner")
    other = account!("draft-other")
    owner_actor = %Human{human_account_id: owner.id}
    other_actor = %Human{human_account_id: other.id}
    regent = Formation.form_regent!("draft-regent", "Draft Regent", actor: owner_actor)

    assert {:ok, draft} =
             Autolaunch.create_launch_draft(
               "Open Research Launch",
               "Open Research",
               "OPEN",
               "A public launch profile awaiting auction design.",
               actor: owner_actor
             )

    assert draft.human_account_id == owner.id
    assert draft.regent_id == regent.id
    assert draft.symbol == "OPEN"

    assert {:ok, [mine]} = Autolaunch.list_my_launch_drafts(actor: owner_actor)
    assert mine.id == draft.id
    assert {:ok, []} = Autolaunch.list_my_launch_drafts(actor: other_actor)
  end

  test "draft creation fails closed without the exact human actor and formed Regent" do
    account = account!("draft-no-regent")

    for actor <- [nil, %{role: :human, human_account_id: account.id}, %System{}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.create_launch_draft("Nope", "Nope", "NOPE", nil, actor: actor)
    end

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.create_launch_draft("No Regent", "No Regent", "NONE", nil,
               actor: %Human{human_account_id: account.id}
             )
  end

  test "draft input uses the current launch vocabulary and remains non-public" do
    account = account!("draft-input")
    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("input-regent", "Input Regent", actor: actor)

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.create_launch_draft("Launch", "Token", "lower", nil, actor: actor)

    assert {:error, %Ash.Error.Invalid{}} = Autolaunch.list_my_launch_drafts()
  end

  defp account!(suffix) do
    Accounts.register_verified!(
      "did:privy:autolaunch-draft:#{suffix}:#{Elixir.System.unique_integer([:positive])}",
      nil,
      [],
      actor: %System{}
    )
  end
end
