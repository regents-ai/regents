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

  test "only the owning human can revise a draft" do
    owner = account!("revision-owner")
    other = account!("revision-other")
    owner_actor = %Human{human_account_id: owner.id}
    Formation.form_regent!("revision-owner-regent", "Revision Owner", actor: owner_actor)

    draft =
      Autolaunch.create_launch_draft!(
        "First title",
        "First token",
        "FIRST",
        "First summary",
        actor: owner_actor
      )

    assert {:ok, revised} =
             Autolaunch.revise_launch_draft(
               draft,
               "Revised title",
               "Revised token",
               "REVISED",
               "Revised summary",
               actor: owner_actor
             )

    assert revised.id == draft.id

    assert {:ok, [persisted]} = Autolaunch.list_my_launch_drafts(actor: owner_actor)

    assert {persisted.title, persisted.token_name, persisted.symbol, persisted.summary} ==
             {"Revised title", "Revised token", "REVISED", "Revised summary"}

    for actor <- [
          nil,
          %Human{human_account_id: other.id},
          %System{},
          %{role: :human, human_account_id: owner.id}
        ] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.revise_launch_draft(
                 persisted,
                 "Not allowed",
                 "Not allowed",
                 "NOPE",
                 nil,
                 actor: actor
               )
    end
  end

  test "invalid revisions leave every stored draft value unchanged" do
    owner = account!("revision-invalid")
    actor = %Human{human_account_id: owner.id}
    Formation.form_regent!("revision-invalid-regent", "Revision Invalid", actor: actor)

    draft =
      Autolaunch.create_launch_draft!(
        "Stable title",
        "Stable token",
        "STABLE",
        "Stable summary",
        actor: actor
      )

    before = stored_values(draft)

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.revise_launch_draft(
               draft,
               "Changed title",
               "Changed token",
               "lowercase",
               "Changed summary",
               actor: actor
             )

    assert {:ok, [persisted]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert stored_values(persisted) == before
  end

  defp account!(suffix) do
    Accounts.register_verified!(
      "did:privy:autolaunch-draft:#{suffix}:#{Elixir.System.unique_integer([:positive])}",
      nil,
      [],
      actor: %System{}
    )
  end

  defp stored_values(draft) do
    Map.take(draft, [
      :id,
      :title,
      :token_name,
      :symbol,
      :summary,
      :human_account_id,
      :regent_id,
      :inserted_at,
      :updated_at
    ])
  end
end
