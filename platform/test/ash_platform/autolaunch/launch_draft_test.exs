defmodule AshPlatform.Autolaunch.LaunchDraftTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch, Formation}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Autolaunch.LaunchDraft

  @draft %{
    "name" => "Open Research",
    "symbol" => "open",
    "description" => "A launch profile awaiting review.",
    "website" => "https://example.test/open",
    "image" => "https://example.test/open.png",
    "treasury" => "0xAbCdeF0000000000000000000000000000000001",
    "required_regent_raised" => "1000.500000000000000001"
  }

  @eoa_acknowledgement "This auction will be owned by my EOA private key, and significant harm and token value will happen if it is lost or compromised. I was warned to create a Gnosis Safe or 0xSplits smart account as the owner, and I realize auction bidders and token owners will see that it is EOA-owned and more risky. I accept these problems, and wish to continue with EOA ownership of the token."

  test "a draft stores the seven clean-V1 fields exactly as written and stays private" do
    owner = account!("owner")
    other = account!("other")
    owner_actor = %Human{human_account_id: owner.id}
    regent = Formation.form_regent!("draft-regent", "Draft Regent", actor: owner_actor)

    assert {:ok, draft} =
             Autolaunch.create_launch_draft(
               Map.put(@draft, "name", "  Open Research  "),
               actor: owner_actor
             )

    assert draft.human_account_id == owner.id
    assert draft.regent_id == regent.id
    assert Map.take(draft, clean_v1_keys()) == expected_values()
    # Nothing invents a value for the superseded launch-page title.
    assert is_nil(draft.title)

    assert {:ok, [mine]} = Autolaunch.list_my_launch_drafts(actor: owner_actor)
    assert mine.id == draft.id
    assert {:ok, []} = Autolaunch.list_my_launch_drafts(actor: %Human{human_account_id: other.id})
  end

  test "drafting fails closed without the exact human actor and a formed Regent" do
    account = account!("no-regent")

    for actor <- [nil, %{role: :human, human_account_id: account.id}, %System{}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.create_launch_draft(@draft, actor: actor)
    end

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.create_launch_draft(@draft, actor: %Human{human_account_id: account.id})

    assert {:error, %Ash.Error.Invalid{}} = Autolaunch.list_my_launch_drafts()
  end

  test "create and revise both require all seven fields" do
    actor = actor_with_regent!("required")
    draft = Autolaunch.create_launch_draft!(@draft, actor: actor)

    for field <- Map.keys(@draft) do
      blanked = Map.put(@draft, field, "   ")

      assert field_errors(Autolaunch.create_launch_draft(blanked, actor: actor)) == %{
               field => "is required"
             }

      assert field_errors(Autolaunch.revise_launch_draft(draft, blanked, actor: actor)) == %{
               field => "is required"
             }
    end
  end

  test "metadata is bounded by UTF-8 byte size while duplicates and any symbol casing pass" do
    actor = actor_with_regent!("metadata")

    for {field, limit} <- [
          {"name", 64},
          {"symbol", 16},
          {"description", 512},
          {"website", 256},
          {"image", 256}
        ] do
      at_limit = Map.put(@draft, field, String.duplicate("a", limit))
      over_limit = Map.put(@draft, field, String.duplicate("a", limit - 1) <> "é")

      assert {:ok, _draft} = Autolaunch.create_launch_draft(at_limit, actor: actor)

      assert field_errors(Autolaunch.create_launch_draft(over_limit, actor: actor)) == %{
               field => "must be #{limit} bytes or fewer"
             }
    end

    assert {:ok, _one} = Autolaunch.create_launch_draft(@draft, actor: actor)
    assert {:ok, _duplicate} = Autolaunch.create_launch_draft(@draft, actor: actor)
  end

  test "the treasury takes any 40-hex address, keeps its casing, and rejects zero" do
    actor = actor_with_regent!("addresses")
    mixed = "0xAbCdeF0000000000000000000000000000000001"
    lowered = String.downcase(mixed)

    for written <- [mixed, lowered] do
      assert {:ok, draft} =
               Autolaunch.create_launch_draft(%{@draft | "treasury" => written}, actor: actor)

      assert draft.treasury == written
    end

    assert field_errors(
             Autolaunch.create_launch_draft(
               Map.put(@draft, "treasury", "0x" <> String.duplicate("0", 40)),
               actor: actor
             )
           ) == %{"treasury" => "cannot be the all-zero address"}

    for bad <- ["0x123", String.duplicate("a", 40), mixed <> "0"] do
      assert field_errors(
               Autolaunch.create_launch_draft(Map.put(@draft, "treasury", bad), actor: actor)
             ) == %{"treasury" => "must start with 0x and hold exactly 40 hexadecimal characters"}
    end
  end

  test "THE_EOA_WARNING_MATCHES_CHARACTER_FOR_CHARACTER_WITHOUT_TRIMMING" do
    actor = actor_with_regent!("eoa-warning")
    eoa = Map.merge(@draft, %{"treasury_path" => "eoa"})

    for wrong <- [
          nil,
          "",
          String.trim_trailing(@eoa_acknowledgement, "."),
          @eoa_acknowledgement <> " "
        ] do
      assert {:error, %Ash.Error.Invalid{}} =
               Autolaunch.create_launch_draft(
                 Map.put(eoa, "eoa_acknowledgement", wrong),
                 actor: actor
               )
    end

    assert {:ok, draft} =
             Autolaunch.create_launch_draft(
               Map.put(eoa, "eoa_acknowledgement", @eoa_acknowledgement),
               actor: actor
             )

    assert draft.treasury_path == :eoa
  end

  test "the required raise is a positive plain decimal with at most 18 fractional digits" do
    actor = actor_with_regent!("raise")
    field = "required_regent_raised"

    for accepted <- ["1", "0.000000000000000001", "1000.5", "12345678901234567890"] do
      assert {:ok, draft} =
               Autolaunch.create_launch_draft(Map.put(@draft, field, accepted), actor: actor)

      assert draft.required_regent_raised == accepted
    end

    for malformed <- ["-1", "+1", "1,000", "1e18", "1.", ".5", "1.0000000000000000001", "abc"] do
      assert field_errors(
               Autolaunch.create_launch_draft(Map.put(@draft, field, malformed), actor: actor)
             ) == %{field => "must be a plain REGENT amount with at most 18 decimal places"}
    end

    for zero <- ["0", "0.0", "0.000000000000000000"] do
      assert field_errors(
               Autolaunch.create_launch_draft(Map.put(@draft, field, zero), actor: actor)
             ) == %{field => "must be greater than zero"}
    end
  end

  # The C4 factory refuses an empty metadata field outright, so a draft a founder
  # can still write must never be able to hold one. Only historical rows may, and
  # launch review is where those are refused.
  test "no new or revised draft can store an empty metadata field" do
    actor = actor_with_regent!("nonempty")
    draft = Autolaunch.create_launch_draft!(@draft, actor: actor)

    for field <- ["name", "symbol", "description", "website", "image"],
        blank <- ["", " ", "\t\n"] do
      blanked = Map.put(@draft, field, blank)

      assert field_errors(Autolaunch.create_launch_draft(blanked, actor: actor)) == %{
               field => "is required"
             }

      assert field_errors(Autolaunch.revise_launch_draft(draft, blanked, actor: actor)) == %{
               field => "is required"
             }
    end

    assert {:ok, [stored]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert Map.take(stored, clean_v1_keys()) == expected_values()
  end

  test "only the owning human revises, and a rejected revision changes nothing" do
    owner = account!("revise-owner")
    other = account!("revise-other")
    owner_actor = %Human{human_account_id: owner.id}
    Formation.form_regent!("revise-regent", "Revise Regent", actor: owner_actor)
    draft = Autolaunch.create_launch_draft!(@draft, actor: owner_actor)

    assert {:ok, revised} =
             Autolaunch.revise_launch_draft(
               draft,
               %{@draft | "name" => "Renamed Research"},
               actor: owner_actor
             )

    assert revised.name == "Renamed Research"

    for actor <- [
          nil,
          %Human{human_account_id: other.id},
          %System{},
          %{role: :human, human_account_id: owner.id}
        ] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.revise_launch_draft(revised, @draft, actor: actor)
    end

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.revise_launch_draft(
               revised,
               %{@draft | "treasury" => "not-an-address"},
               actor: owner_actor
             )

    assert {:ok, [persisted]} = Autolaunch.list_my_launch_drafts(actor: owner_actor)
    assert Map.take(persisted, clean_v1_keys()) == %{expected_values() | name: "Renamed Research"}
  end

  test "a draft written before clean V1 stays readable and can be completed by revising" do
    owner = account!("legacy")
    actor = %Human{human_account_id: owner.id}
    regent = Formation.form_regent!("legacy-regent", "Legacy Regent", actor: actor)

    Ash.Seed.seed!(LaunchDraft, %{
      title: "Superseded launch title",
      name: "Legacy Research",
      symbol: "LEGACY",
      human_account_id: owner.id,
      regent_id: regent.id
    })

    assert {:ok, [legacy]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert {legacy.name, legacy.symbol} == {"Legacy Research", "LEGACY"}
    assert is_nil(legacy.description)
    assert is_nil(legacy.treasury)

    assert {:ok, completed} = Autolaunch.revise_launch_draft(legacy, @draft, actor: actor)
    assert Map.take(completed, clean_v1_keys()) == expected_values()
    # Completing a row never rewrites or discards what it already held.
    assert completed.title == "Superseded launch title"
  end

  defp clean_v1_keys do
    [
      :name,
      :symbol,
      :description,
      :website,
      :image,
      :treasury,
      :required_regent_raised
    ]
  end

  defp expected_values, do: Map.new(@draft, fn {field, value} -> {:"#{field}", value} end)

  defp field_errors({:error, %Ash.Error.Invalid{errors: errors}}) do
    Map.new(errors, fn
      %Ash.Error.Changes.Required{field: field} -> {to_string(field), "is required"}
      %{field: field, message: message} -> {to_string(field), message}
    end)
  end

  defp actor_with_regent!(suffix) do
    actor = %Human{human_account_id: account!(suffix).id}
    Formation.form_regent!("#{suffix}-regent", "Regent #{suffix}", actor: actor)
    actor
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
