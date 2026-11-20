defmodule RegentsWeb.Techtree.BootstrapController do
  @moduledoc """
  The published installation contract for this channel, byte for byte.

  Every executable instruction in the payload is an array of arguments. A host
  agent or an installer runs the array; nothing here — and nothing on the
  server — ever runs a string. The payload also carries no credential of any
  kind: what a participant needs to supply is theirs to supply.

  The stored payload is hashed again before it is sent, so a row that drifted
  from the digest it was imported under is refused rather than published.
  """

  use RegentsWeb, :controller

  alias Regents.Techtree.Catalog.Bundle
  alias Regents.Techtree.Catalog.Query
  alias RegentsWeb.Techtree.ExactResponse

  @doc """
  Return the exact bootstrap payload of the active release.
  """
  def show(conn, _params) do
    case Query.bootstrap_payload() do
      {:ok, payload, digest} ->
        ExactResponse.send_exact(conn, payload, Bundle.json_media_type(), digest, :revalidated)

      {:error, error} ->
        ExactResponse.send_error(conn, error)
    end
  end
end
