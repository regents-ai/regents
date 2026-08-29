defmodule AshPlatform.Autolaunch.LaunchDraftTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch, Formation}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Autolaunch.{LaunchDraft, LaunchDraftImageStorage}

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

  test "a Human owns a partial draft directly without a Regent" do
    owner = account!("owner")
    other = account!("other")
    actor = %Human{human_account_id: owner.id}

    assert {:ok, draft} =
             Autolaunch.create_launch_draft(%{"name" => "  Open Research  "}, actor: actor)

    assert draft.human_account_id == owner.id
    assert is_nil(draft.regent_id)
    assert draft.name == "Open Research"
    assert draft.symbol == ""
    refute LaunchDraft.token_details_complete?(draft)
    refute LaunchDraft.treasury_complete?(draft)

    assert {:ok, [mine]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert mine.id == draft.id
    assert {:ok, []} = Autolaunch.list_my_launch_drafts(actor: %Human{human_account_id: other.id})
  end

  test "draft creation and reads require the exact Human actor" do
    account = account!("actor")

    for actor <- [nil, %{role: :human, human_account_id: account.id}, %System{}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.create_launch_draft(%{"name" => "Private"}, actor: actor)
    end

    assert {:error, %Ash.Error.Invalid{}} = Autolaunch.list_my_launch_drafts()
  end

  test "owner autosave persists bounded incomplete text and refuses cross-account writes" do
    owner = account!("autosave-owner")
    other = account!("autosave-other")
    actor = %Human{human_account_id: owner.id}
    other_actor = %Human{human_account_id: other.id}
    draft = Autolaunch.create_launch_draft!(%{}, actor: actor)

    assert {:ok, token_partial} =
             Autolaunch.autosave_launch_token_details(
               draft,
               %{
                 "name" => "Partial",
                 "symbol" => "",
                 "description" => "Still writing",
                 "website" => "not a complete URL yet",
                 "required_regent_raised" => "1."
               },
               actor: actor
             )

    assert token_partial.name == "Partial"
    assert token_partial.description == "Still writing"
    refute LaunchDraft.token_details_complete?(token_partial)

    assert {:ok, treasury_partial} =
             Autolaunch.autosave_launch_treasury(
               token_partial,
               %{
                 "treasury" => "0x123",
                 "treasury_path" => "eoa",
                 "eoa_acknowledgement" => "typing"
               },
               actor: actor
             )

    assert treasury_partial.treasury == "0x123"
    assert treasury_partial.eoa_acknowledgement == "typing"
    refute LaunchDraft.treasury_complete?(treasury_partial)

    assert {:error, %Ash.Error.Forbidden{}} =
             Autolaunch.autosave_launch_token_details(
               treasury_partial,
               %{"name" => "Stolen"},
               actor: other_actor
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.autosave_launch_token_details(
               treasury_partial,
               %{"description" => String.duplicate("x", 513)},
               actor: actor
             )

    assert {:ok, [persisted]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert persisted.name == "Partial"
    assert persisted.treasury == "0x123"
  end

  test "stage completion and final revision use the exact launch requirements" do
    actor = %Human{human_account_id: account!("complete").id}
    draft = Autolaunch.create_launch_draft!(%{}, actor: actor)

    token_details = Map.take(@draft, ~w(name symbol description website required_regent_raised))

    assert {:ok, token} =
             Autolaunch.autosave_launch_token_details(draft, token_details, actor: actor)

    refute LaunchDraft.token_details_complete?(token)

    assert {:ok, %{draft: token}} =
             LaunchDraftImageStorage.store_and_attach(
               token,
               png(),
               "image/png",
               "open.png",
               actor
             )

    assert LaunchDraft.token_details_complete?(token)
    refute LaunchDraft.launch_ready?(token)

    assert {:ok, safe} =
             Autolaunch.autosave_launch_treasury(
               token,
               Map.take(@draft, ["treasury"]),
               actor: actor
             )

    assert LaunchDraft.treasury_complete?(safe)
    assert LaunchDraft.launch_ready?(safe)

    assert {:ok, _final} =
             Autolaunch.revise_launch_draft(safe, Map.delete(@draft, "image"), actor: actor)

    assert {:ok, eoa_wrong} =
             Autolaunch.autosave_launch_treasury(
               safe,
               %{
                 "treasury" => @draft["treasury"],
                 "treasury_path" => "eoa",
                 "eoa_acknowledgement" => "almost"
               },
               actor: actor
             )

    refute LaunchDraft.treasury_complete?(eoa_wrong)

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.revise_launch_draft(
               eoa_wrong,
               Map.merge(Map.delete(@draft, "image"), %{
                 "treasury_path" => "eoa",
                 "eoa_acknowledgement" => "almost"
               }),
               actor: actor
             )

    assert {:ok, eoa} =
             Autolaunch.autosave_launch_treasury(
               eoa_wrong,
               %{"eoa_acknowledgement" => @eoa_acknowledgement},
               actor: actor
             )

    assert LaunchDraft.launch_ready?(eoa)
  end

  test "account-owned stage completion requires the exact loaded owned image" do
    actor = %Human{human_account_id: account!("loaded-image").id}
    draft = Autolaunch.create_launch_draft!(Map.delete(@draft, "image"), actor: actor)

    assert {:ok, %{draft: loaded}} =
             LaunchDraftImageStorage.store_and_attach(
               draft,
               png(),
               "image/png",
               "loaded.png",
               actor
             )

    assert LaunchDraft.token_details_complete?(loaded)

    refute LaunchDraft.token_details_complete?(%{loaded | launch_draft_image: %Ash.NotLoaded{}})

    refute LaunchDraft.token_details_complete?(%{
             loaded
             | launch_draft_image: %{
                 loaded.launch_draft_image
                 | digest: String.duplicate("0", 64)
               }
           })

    refute LaunchDraft.token_details_complete?(%{
             loaded
             | image:
                 String.replace_suffix(
                   loaded.image,
                   loaded.launch_draft_image.digest,
                   String.duplicate("0", 64)
                 )
           })
  end

  test "final validation keeps metadata, treasury, and raise bounds" do
    actor = %Human{human_account_id: account!("validation").id}
    draft = Autolaunch.create_launch_draft!(Map.delete(@draft, "image"), actor: actor)

    assert {:ok, %{draft: draft}} =
             LaunchDraftImageStorage.store_and_attach(
               draft,
               png(),
               "image/png",
               "validation.png",
               actor
             )

    for {field, value, message} <- [
          {"name", "", "is required"},
          {"description", String.duplicate("a", 513), "must be 512 bytes or fewer"},
          {"treasury", "0x123", "must start with 0x"},
          {"required_regent_raised", "0", "must be greater than zero"}
        ] do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Autolaunch.revise_launch_draft(
                 draft,
                 @draft |> Map.delete("image") |> Map.put(field, value),
                 actor: actor
               )

      assert Exception.message(error) =~ message
    end
  end

  test "a historical Regent-linked draft stays readable without rewriting provenance" do
    owner = account!("legacy")
    actor = %Human{human_account_id: owner.id}
    regent = Formation.form_regent!("legacy-regent", "Legacy Regent", actor: actor)

    legacy =
      Ash.Seed.seed!(LaunchDraft, %{
        title: "Superseded launch title",
        name: "Legacy Research",
        symbol: "LEGACY",
        human_account_id: owner.id,
        regent_id: regent.id
      })

    assert {:ok, revised} = Autolaunch.revise_launch_draft(legacy, @draft, actor: actor)
    assert revised.regent_id == regent.id
    assert revised.title == "Superseded launch title"
    assert LaunchDraft.launch_ready?(revised)
  end

  test "account-owned drafts refuse raw image input while legacy Regent drafts retain it" do
    owner = account!("raw-image")
    actor = %Human{human_account_id: owner.id}

    assert {:error, %Ash.Error.Invalid{} = create_error} =
             Autolaunch.create_launch_draft(@draft, actor: actor)

    assert Exception.message(create_error) =~ "No such input `image`"

    draft = Autolaunch.create_launch_draft!(Map.delete(@draft, "image"), actor: actor)

    assert {:error, %Ash.Error.Invalid{} = autosave_error} =
             Autolaunch.autosave_launch_token_details(
               draft,
               %{"image" => @draft["image"]},
               actor: actor
             )

    assert Exception.message(autosave_error) =~ "No such input `image`"

    assert {:error, %Ash.Error.Invalid{} = revise_error} =
             Autolaunch.revise_launch_draft(draft, @draft, actor: actor)

    assert Exception.message(revise_error) =~ "managed by this account's immutable image upload"

    regent = Formation.form_regent!("legacy-image", "Legacy Image", actor: actor)

    legacy =
      Ash.Seed.seed!(LaunchDraft, %{
        name: "Legacy",
        symbol: "LEG",
        human_account_id: owner.id,
        regent_id: regent.id
      })

    assert {:ok, legacy} = Autolaunch.revise_launch_draft(legacy, @draft, actor: actor)
    assert legacy.image == @draft["image"]
    assert LaunchDraft.image_complete?(legacy)
  end

  defp account!(suffix) do
    Accounts.register_verified!(
      "did:privy:autolaunch-draft:#{suffix}:#{Elixir.System.unique_integer([:positive])}",
      nil,
      [],
      actor: %System{}
    )
  end

  defp png,
    do:
      File.read!(
        "priv/static/notebooks/2152a57337000ef5b8e2233d4cad237d4edbd92131cdec553437aef422719f3b/favicon-16x16.png"
      )
end
