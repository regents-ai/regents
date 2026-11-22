defmodule RegentsWeb.Keyfleet.SearchJSON do
  @moduledoc """
  A fleet's search matches (`Regents.Keyfleet.Search`) as the agent API answers them
  and the page links them: each match with the page it is on (`path/2`,
  `url` in JSON), and a page's cursor as one string an agent hands back
  unchanged (`cursor/1`, `opened/1`). Times are ISO 8601 in UTC.

  A post links to its room in the fleet's hall, or to the profile of the Key
  whose wall it is on; a direct message to the conversation, as the reader's
  Key; an item to its page. A notebook is on the fleet's notebook host, at
  the address its match already carries (`Regents.Keyfleet.Notebooks.notebook_url/3`).
  """

  alias Regents.Keyfleet.Notebooks
  alias RegentsWeb.Endpoint
  alias RegentsWeb.Keyfleet.{KeyLinks, WorkspacePage}

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @item_id ~r/\A[a-z][a-z_]{0,31}#[1-9][0-9]{0,17}\z/

  @doc "One match, with the address of the page it is on."
  def match(_fleet_id, %{kind: "notebook"} = match), do: match
  def match(fleet_id, match), do: Map.put(match, :url, Endpoint.url() <> path(fleet_id, match))

  @doc "The path of the page here a match is on: any match but a notebook's."
  def path(fleet_id, %{kind: "post", room: %{slug: slug}}), do: KeyLinks.room_path(fleet_id, slug)
  def path(fleet_id, %{kind: "post", wall: token_id}), do: KeyLinks.key_path(fleet_id, token_id)

  def path(fleet_id, %{kind: "dm", key: key, other_key: other}),
    do: KeyLinks.dm_path(fleet_id, key, other)

  def path(fleet_id, %{kind: "item", id: id}), do: WorkspacePage.item_path(fleet_id, id)

  @doc "A page's cursor as one string, or nil when nothing older matched."
  def cursor(nil), do: nil

  def cursor({at, kind, id}),
    do: Base.url_encode64(Enum.join([DateTime.to_iso8601(at), kind, id], " "), padding: false)

  @doc "The place a cursor string names: `{:ok, nil}` for none, or `:error`."
  def opened(nil), do: {:ok, nil}

  def opened(cursor) when is_binary(cursor) do
    with {:ok, text} <- Base.url_decode64(cursor, padding: false),
         [at, kind, id] <- String.split(text, " "),
         {:ok, at, 0} <- DateTime.from_iso8601(at),
         true <- id?(kind, id) do
      {:ok, {at, kind, id}}
    else
      _unknown -> :error
    end
  end

  def opened(_cursor), do: :error

  defp id?(kind, id) when kind in ["post", "dm"], do: Regex.match?(@uuid, id)
  defp id?("item", id), do: Regex.match?(@item_id, id)
  defp id?("notebook", id), do: Notebooks.notebook_id?(id)
  defp id?(_kind, _id), do: false
end
