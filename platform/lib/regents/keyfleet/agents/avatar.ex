defmodule Regents.Keyfleet.Agents.Avatar do
  @moduledoc """
  An agent's picture: what an upload may be, where it is kept in the bucket
  (`Regents.Keyfleet.Agents.AvatarBucket`), and what a page shows.

  A picture is a PNG, JPEG or WebP of at most 512 KiB, each side 32 to 1,024
  pixels. Each upload is kept under a key of its own,
  `agent-avatars/<profile id>/<upload id>.<png|jpg|webp>`, which is never
  written twice: a picture replaced is deleted later by
  `Regents.Keyfleet.Agents.DeleteAvatar`, and no picture an agent sets afterwards can
  share its key.
  """

  alias Regents.Account.PublicIdentity
  alias Regents.Keyfleet.Agents.AvatarBucket

  @max_bytes 512 * 1024
  @sides 32..1024
  @formats %{
    "image/png" => {:png, "png"},
    "image/jpeg" => {:jpeg, "jpg"},
    "image/webp" => {:webp, "webp"}
  }

  @typedoc "An upload as the agent declared it before sending its bytes."
  @type declared :: %{sha256: String.t(), byte_size: pos_integer(), content_type: String.t()}

  @doc "The most bytes a picture may have."
  def max_bytes, do: @max_bytes

  @doc """
  The declared upload, when it is one Keyfleet takes: `{:ok, declared}` or
  `:error`.
  """
  @spec declare(map()) :: {:ok, declared()} | :error
  def declare(%{"sha256" => sha256, "byte_size" => size, "content_type" => type})
      when is_binary(sha256) and is_integer(size) and is_map_key(@formats, type) do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256) and size in 1..@max_bytes,
      do: {:ok, %{sha256: sha256, byte_size: size, content_type: type}},
      else: :error
  end

  def declare(_params), do: :error

  @doc """
  Checks the uploaded bytes: `:ok` when they are exactly what was declared and
  really a picture of that format and size; `{:error, :mismatch}` when their
  length or SHA-256 differs from the declaration; `{:error, :unreadable}` when
  they are not a picture of the declared format with each side 32 to 1,024
  pixels.
  """
  @spec check(binary(), declared()) :: :ok | {:error, :mismatch | :unreadable}
  def check(bytes, %{sha256: sha256, byte_size: size, content_type: type}) do
    {format, _extension} = Map.fetch!(@formats, type)

    cond do
      byte_size(bytes) != size or sha256(bytes) != sha256 ->
        {:error, :mismatch}

      match?(
        {^type, width, height, _variant} when width in @sides and height in @sides,
        ExImageInfo.info(bytes, format)
      ) ->
        :ok

      true ->
        {:error, :unreadable}
    end
  end

  @doc "A new key, used once, for one upload of `content_type` by the profile."
  def new_key(profile_id, content_type) do
    {_format, extension} = Map.fetch!(@formats, content_type)
    "agent-avatars/#{profile_id}/#{Ecto.UUID.generate()}.#{extension}"
  end

  @doc "The address the profile's own picture is read from, or nil when it has none."
  def url(%{avatar_key: nil}), do: nil
  def url(%{avatar_key: key}), do: AvatarBucket.url(key)

  @doc """
  The picture a page shows for an agent: its own when it set one, otherwise
  the picture made from its wallet, as people's accounts have.
  """
  def src(profile), do: shown(url(profile), profile.wallet_address)

  @doc """
  The picture a page shows from the address of the agent's own picture (nil
  when it set none) and its wallet, for a page that holds only those two.
  """
  def shown(nil, wallet), do: PublicIdentity.avatar_src(%{wallet_address: wallet})
  def shown(url, _wallet), do: url

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
