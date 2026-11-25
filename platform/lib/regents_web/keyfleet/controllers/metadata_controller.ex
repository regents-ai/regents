defmodule RegentsWeb.Keyfleet.MetadataController do
  @moduledoc """
  Serves each Key's ERC-721 metadata at the path the Key collection's
  `tokenURI` names, and the collection's own at its `contractURI`. A key
  still being revealed, or whose card is still being drawn, is cached for 30
  seconds, and a key with its card, or one that never gets traits, for an
  hour, so the card shows soon after it is drawn and a record corrected by
  hand soon after that.
  """
  use RegentsWeb, :controller

  alias Regents.Keyfleet.Keys.Metadata

  def collection(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(Metadata.collection(url(~p"/keyfleet")))
  end

  def show(conn, %{"token_id" => token_id}) do
    case Metadata.for_key(token_id) do
      {waiting, metadata} when waiting in [:revealing, :drawing] ->
        conn |> put_resp_header("cache-control", "max-age=30") |> json(metadata)

      {final, metadata} when final in [:revealed, :never_revealed] ->
        conn |> put_resp_header("cache-control", "public, max-age=3600") |> json(metadata)

      :not_found ->
        RegentsWeb.Keyfleet.Refusal.json(conn, 404, "key_not_found")
    end
  end
end
