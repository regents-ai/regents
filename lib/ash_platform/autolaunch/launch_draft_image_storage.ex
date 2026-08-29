defmodule AshPlatform.Autolaunch.LaunchDraftImageStorage do
  @moduledoc """
  Validates and stores one immutable launch image, then attaches its permanent
  content-addressed URL to the owner's draft in the same database transaction.
  """

  require Ash.Query

  alias AshPlatform.Accounts.HumanAccount
  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch
  alias AshPlatform.Autolaunch.{LaunchDraft, LaunchDraftImage}

  @maximum_bytes 2_097_152
  @content_types ["image/png", "image/jpeg", "image/webp"]

  @type stored :: %{
          image: Ash.Resource.record(),
          draft: Ash.Resource.record(),
          reused?: boolean()
        }

  @spec store_and_attach(Ash.Resource.record(), binary(), String.t(), struct()) ::
          {:ok, stored()} | {:error, term()}
  def store_and_attach(
        %LaunchDraft{human_account_id: owner_id} = draft,
        bytes,
        declared_type,
        %Human{human_account_id: owner_id} = actor
      ) do
    with {:ok, content_type} <- validate(bytes, declared_type) do
      transact(draft, bytes, content_type, sha256(bytes), actor)
    end
  end

  def store_and_attach(_draft, _bytes, _declared_type, _actor), do: {:error, :image_unavailable}

  @spec public_url(Ash.Resource.record()) :: String.t()
  def public_url(%LaunchDraftImage{id: id, digest: digest}) do
    AshPlatformWeb.Endpoint.url() <> "/autolaunch/images/#{id}/#{digest}"
  end

  @spec validate(binary(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate(bytes, declared_type)
      when is_binary(bytes) and declared_type in @content_types and
             byte_size(bytes) in 1..@maximum_bytes do
    if signature?(bytes, declared_type), do: {:ok, declared_type}, else: {:error, :invalid_image}
  end

  def validate(bytes, _declared_type) when is_binary(bytes) and byte_size(bytes) > @maximum_bytes,
    do: {:error, :image_too_large}

  def validate(_bytes, _declared_type), do: {:error, :invalid_image}

  defp transact(draft, bytes, content_type, digest, actor) do
    Ash.DataLayer.transaction(LaunchDraftImage, fn ->
      store_transaction(draft, bytes, content_type, digest, actor)
    end)
  end

  defp store_transaction(draft, bytes, content_type, digest, actor) do
    with {:ok, _account} <- lock_owner(actor),
         {:ok, image, reused?} <- existing_or_store(bytes, content_type, digest, actor),
         url <- public_url(image),
         :ok <- bounded_url(url),
         {:ok, attached} <- attach(draft, image, url, actor) do
      %{image: image, draft: attached, reused?: reused?}
    else
      {:error, error} -> Ash.DataLayer.rollback(LaunchDraftImage, error)
    end
  end

  defp lock_owner(%Human{human_account_id: id} = actor) do
    HumanAccount
    |> Ash.Query.for_read(:read_self, %{id: id}, actor: actor)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(actor: actor)
    |> case do
      {:ok, nil} -> {:error, :image_unavailable}
      result -> result
    end
  end

  defp existing_or_store(bytes, content_type, digest, actor) do
    case Autolaunch.get_my_launch_draft_image_by_digest(digest, actor: actor) do
      {:ok, nil} ->
        store_first_image(bytes, content_type, digest, actor)

      {:ok, image} ->
        {:ok, image, true}

      {:error, error} ->
        {:error, error}
    end
  end

  defp store_first_image(bytes, content_type, digest, actor) do
    case Autolaunch.list_my_launch_draft_images(actor: actor) do
      {:ok, []} -> create_image(bytes, content_type, digest, actor)
      {:ok, [_existing | _]} -> {:error, :image_limit_reached}
      {:error, error} -> {:error, error}
    end
  end

  defp create_image(bytes, content_type, digest, actor) do
    case Autolaunch.store_launch_draft_image(
           digest,
           content_type,
           byte_size(bytes),
           bytes,
           actor: actor
         ) do
      {:ok, image} -> {:ok, image, false}
      {:error, error} -> {:error, error}
    end
  end

  defp attach(draft, image, url, actor) do
    Autolaunch.attach_launch_draft_image(draft, url, image.id, actor: actor)
  end

  defp bounded_url(url) when is_binary(url) and byte_size(url) <= 256, do: :ok
  defp bounded_url(_url), do: {:error, :image_url_too_long}

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp signature?(bytes, "image/png") do
    with <<137, "PNG\r\n", 26, 10, rest::binary>> <- bytes,
         true <- byte_size(rest) >= 25,
         <<_length::32, "IHDR", _::binary>> <- rest,
         true <- png_ends_with_iend?(bytes) do
      true
    else
      _ -> false
    end
  end

  defp signature?(<<255, 216, 255, _rest::binary>> = bytes, "image/jpeg"),
    do: byte_size(bytes) >= 6 and binary_part(bytes, byte_size(bytes) - 2, 2) == <<255, 217>>

  defp signature?(
         <<"RIFF", declared_size::little-32, "WEBP", _rest::binary>> = bytes,
         "image/webp"
       ),
       do: declared_size + 8 == byte_size(bytes) and byte_size(bytes) >= 16

  defp signature?(_bytes, _content_type), do: false

  defp png_ends_with_iend?(bytes) do
    byte_size(bytes) >= 12 and
      binary_part(bytes, byte_size(bytes) - 12, 8) == <<0, 0, 0, 0, "IEND">>
  end
end
