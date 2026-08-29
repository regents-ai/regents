defmodule AshPlatform.Autolaunch.LaunchDraftImageStorageTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Autolaunch.LaunchDraftImageStorage

  test "PNG, JPEG, and WebP require matching complete signatures" do
    assert {:ok, "image/png"} = LaunchDraftImageStorage.validate(png(), "image/png")
    assert {:ok, "image/jpeg"} = LaunchDraftImageStorage.validate(jpeg(), "image/jpeg")
    assert {:ok, "image/webp"} = LaunchDraftImageStorage.validate(webp(), "image/webp")

    assert {:error, :invalid_image} = LaunchDraftImageStorage.validate(png(), "image/jpeg")
    assert {:error, :invalid_image} = LaunchDraftImageStorage.validate(jpeg(), "image/webp")
    assert {:error, :invalid_image} = LaunchDraftImageStorage.validate(webp(), "image/png")

    assert {:error, :invalid_image} =
             LaunchDraftImageStorage.validate("<svg></svg>", "image/svg+xml")

    assert {:error, :invalid_image} =
             LaunchDraftImageStorage.validate(binary_part(png(), 0, 20), "image/png")

    assert {:error, :invalid_image} =
             LaunchDraftImageStorage.validate(binary_part(jpeg(), 0, 5), "image/jpeg")

    assert {:error, :image_too_large} =
             LaunchDraftImageStorage.validate(
               String.duplicate("x", 2_097_153),
               "image/png"
             )
  end

  test "image dimensions are advisory and a valid 1 by 1 PNG is accepted" do
    actor = actor!("non-400-image")
    draft = Autolaunch.create_launch_draft!(%{}, actor: actor)

    assert {:ok, %{image: image}} =
             LaunchDraftImageStorage.store_and_attach(draft, png(), "image/png", actor)

    assert image.content_type == "image/png"
    assert image.byte_size == byte_size(png())
  end

  test "one immutable image is stored transactionally, attached, and exact repeats deduplicate" do
    actor = actor!("one-image")
    draft = Autolaunch.create_launch_draft!(%{}, actor: actor)

    assert {:ok, first} =
             LaunchDraftImageStorage.store_and_attach(draft, png(), "image/png", actor)

    assert first.reused? == false
    assert first.image.byte_size == byte_size(png())
    assert first.draft.launch_draft_image_id == first.image.id
    assert first.draft.image == LaunchDraftImageStorage.public_url(first.image)
    assert byte_size(first.draft.image) <= 256

    assert {:ok, repeat} =
             LaunchDraftImageStorage.store_and_attach(first.draft, png(), "image/png", actor)

    assert repeat.reused?
    assert repeat.image.id == first.image.id
    assert repeat.draft.image == first.draft.image
    assert {:ok, [only]} = Autolaunch.list_my_launch_draft_images(actor: actor)
    assert only.id == first.image.id
  end

  test "a different second image fails without replacing or deleting the first" do
    actor = actor!("second-refused")
    draft = Autolaunch.create_launch_draft!(%{}, actor: actor)

    assert {:ok, first} =
             LaunchDraftImageStorage.store_and_attach(draft, png(), "image/png", actor)

    assert {:error, :image_limit_reached} =
             LaunchDraftImageStorage.store_and_attach(first.draft, jpeg(), "image/jpeg", actor)

    assert {:ok, [persisted]} = Autolaunch.list_my_launch_draft_images(actor: actor)
    assert persisted.id == first.image.id
    assert {:ok, [saved_draft]} = Autolaunch.list_my_launch_drafts(actor: actor)
    assert saved_draft.launch_draft_image_id == first.image.id
    assert saved_draft.image == first.draft.image
  end

  test "concurrent different first uploads still create only one immutable owner row" do
    actor = actor!("concurrent-first")
    draft = Autolaunch.create_launch_draft!(%{}, actor: actor)
    parent = self()

    upload = fn bytes, type ->
      Task.async(fn ->
        send(parent, {:ready, self()})
        receive do: (:go -> LaunchDraftImageStorage.store_and_attach(draft, bytes, type, actor))
      end)
    end

    png_upload = upload.(png(), "image/png")
    jpeg_upload = upload.(jpeg(), "image/jpeg")

    assert_receive {:ready, png_pid}
    assert_receive {:ready, jpeg_pid}
    send(png_pid, :go)
    send(jpeg_pid, :go)

    results = [Task.await(png_upload), Task.await(jpeg_upload)]

    assert Enum.count(results, &match?({:ok, _stored}, &1)) == 1
    assert Enum.count(results, &match?({:error, :image_limit_reached}, &1)) == 1
    assert {:ok, [_only]} = Autolaunch.list_my_launch_draft_images(actor: actor)
  end

  test "the same bytes are private per Human and cross-account attachment is refused" do
    owner = actor!("image-owner")
    other = actor!("image-other")
    draft = Autolaunch.create_launch_draft!(%{}, actor: owner)

    assert {:error, :image_unavailable} =
             LaunchDraftImageStorage.store_and_attach(draft, png(), "image/png", other)

    assert {:ok, []} = Autolaunch.list_my_launch_draft_images(actor: owner)
    assert {:ok, []} = Autolaunch.list_my_launch_draft_images(actor: other)

    assert {:ok, owner_image} =
             LaunchDraftImageStorage.store_and_attach(draft, png(), "image/png", owner)

    other_draft = Autolaunch.create_launch_draft!(%{}, actor: other)

    assert {:ok, other_image} =
             LaunchDraftImageStorage.store_and_attach(other_draft, png(), "image/png", other)

    refute owner_image.image.id == other_image.image.id
    assert owner_image.image.digest == other_image.image.digest
  end

  test "the actorless public read requires exact UUID and full digest" do
    actor = actor!("public")
    draft = Autolaunch.create_launch_draft!(%{}, actor: actor)

    assert {:ok, %{image: image}} =
             LaunchDraftImageStorage.store_and_attach(draft, webp(), "image/webp", actor)

    assert {:ok, public} =
             Autolaunch.get_public_launch_draft_image(image.id, image.digest, actor: nil)

    assert public.bytes == webp()
    assert public.content_type == "image/webp"

    wrong = String.duplicate("0", 64)
    assert {:ok, nil} = Autolaunch.get_public_launch_draft_image(image.id, wrong, actor: nil)
    assert {:error, %Ash.Error.Invalid{}} = Autolaunch.list_my_launch_draft_images()
  end

  defp actor!(suffix) do
    account =
      Accounts.register_verified!(
        "did:privy:launch-image:#{suffix}:#{Elixir.System.unique_integer([:positive])}",
        nil,
        [],
        actor: %System{}
      )

    %Human{human_account_id: account.id}
  end

  defp png do
    <<
      137,
      "PNG\r\n",
      26,
      10,
      13::32,
      "IHDR",
      1::32,
      1::32,
      8,
      6,
      0,
      0,
      0,
      0::32,
      0::32,
      "IEND",
      0::32
    >>
  end

  defp jpeg, do: <<255, 216, 255, 224, 0, 0, 255, 217>>
  defp webp, do: <<"RIFF", 8::little-32, "WEBP", "VP8 ">>
end
