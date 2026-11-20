defmodule Regents.Techtree.Catalog.Digest do
  @moduledoc """
  Content addresses over raw catalog bytes.

  Every protocol object in a Techtree catalog is addressed by the SHA-256 of the
  exact bytes `techtree-python` generated. This module hashes those bytes and
  nothing else: it does not canonicalize JSON, and it never decodes an object in
  order to re-encode it. Byte equality is the whole contract, so a document that
  differs only in whitespace is a different object here — which is the point,
  because the website republishes bytes it did not produce.

  A digest is spelled `sha256:` followed by exactly 64 lowercase hexadecimal
  characters. Uppercase is rejected rather than downcased: a caller asking for
  a digest the catalog does not spell that way is asking for something else.
  """

  @prefix "sha256:"
  @hex_length 64

  @doc """
  Whether a value is a digest this catalog can address an object by.

      iex> Regents.Techtree.Catalog.Digest.valid?(Regents.Techtree.Catalog.Digest.hash_bytes("{}"))
      true

      iex> Regents.Techtree.Catalog.Digest.valid?("sha256:ABC")
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(@prefix <> hex) when byte_size(hex) == @hex_length, do: lowercase_hex?(hex)
  def valid?(_other), do: false

  @doc """
  The digest of exactly these bytes.

      iex> Regents.Techtree.Catalog.Digest.hash_bytes("")
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  """
  @spec hash_bytes(binary()) :: String.t()
  def hash_bytes(bytes) when is_binary(bytes) do
    @prefix <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  end

  defp lowercase_hex?(hex) do
    for <<character <- hex>>, reduce: true do
      acc -> acc and character in ~c"0123456789abcdef"
    end
  end
end
