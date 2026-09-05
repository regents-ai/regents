defmodule AshPlatform.Formation.RegentTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation}
  alias AshPlatform.Actors.{Human, System}

  test "one signed-in human forms one Regent and may update its public profile" do
    account = account!("owner")
    actor = %Human{human_account_id: account.id}

    assert {:ok, regent} = Formation.form_regent("atlas", "Atlas", actor: actor)
    assert regent.human_account_id == account.id
    assert regent.slug == "atlas"
    assert regent.display_name == "Atlas"

    assert {:ok, mine} = Formation.get_my_regent(actor: actor)
    assert mine.id == regent.id

    assert {:ok, updated} =
             Formation.update_profile(regent, "Atlas Regent", "Research and synthesis.",
               actor: actor
             )

    assert updated.display_name == "Atlas Regent"
    assert updated.summary == "Research and synthesis."
  end

  test "a human cannot form a second Regent and slugs are globally unique" do
    first = account!("first")
    second = account!("second")

    assert {:ok, _regent} =
             Formation.form_regent("first-regent", "First Regent",
               actor: %Human{human_account_id: first.id}
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Formation.form_regent("another-regent", "Another Regent",
               actor: %Human{human_account_id: first.id}
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Formation.form_regent("first-regent", "Different Regent",
               actor: %Human{human_account_id: second.id}
             )
  end

  test "formation and profile updates require the exact owner principal" do
    owner = account!("owner-policy")
    other = account!("other-policy")
    owner_actor = %Human{human_account_id: owner.id}

    for actor <- [nil, %{role: :human, human_account_id: owner.id}, %System{}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Formation.form_regent(
                 "forbidden-#{Elixir.System.unique_integer([:positive])}",
                 "Nope",
                 actor: actor
               )
    end

    regent = Formation.form_regent!("owner-regent", "Owner Regent", actor: owner_actor)

    assert {:error, %Ash.Error.Forbidden{}} =
             Formation.update_profile(regent, "Taken", nil,
               actor: %Human{human_account_id: other.id}
             )
  end

  test "public slug reads expose the public profile and unknown slugs return nil" do
    account = account!("public")

    regent =
      Formation.form_regent!("public-regent", "Public Regent",
        actor: %Human{human_account_id: account.id}
      )

    assert {:ok, public} = Formation.get_public_regent("public-regent")
    assert public.id == regent.id
    assert public.display_name == "Public Regent"
    assert public.slug == "public-regent"
    refute Map.has_key?(Map.from_struct(public), :privy_user_id)
    refute Map.has_key?(Map.from_struct(public), :wallet_address)

    assert {:ok, nil} = Formation.get_public_regent("missing-regent")
  end

  defp account!(suffix) do
    Accounts.register_verified!(
      "did:privy:formation-regent:#{suffix}:#{Elixir.System.unique_integer([:positive])}",
      nil,
      [],
      actor: %System{}
    )
  end
end
