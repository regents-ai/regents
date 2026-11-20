defmodule RegentsWeb.Techtree.CatalogController do
  @moduledoc """
  The generated catalog index, exactly as it was generated.

  The bytes are not decoded and re-encoded on the way out. They already have a
  digest, they were already validated by the protocol implementation that
  produced them, and a JSON encoder here would quietly create a second
  representation of the same catalog with a different address.
  """

  use RegentsWeb, :controller

  alias Regents.Techtree.Catalog.Bundle
  alias Regents.Techtree.Catalog.Query
  alias RegentsWeb.Techtree.ExactResponse

  @doc """
  Return the exact catalog index of the active release.
  """
  def index(conn, _params) do
    case Query.catalog_bytes() do
      {:ok, bytes, digest} ->
        ExactResponse.send_exact(conn, bytes, Bundle.json_media_type(), digest, :revalidated)

      {:error, error} ->
        ExactResponse.send_error(conn, error)
    end
  end
end
