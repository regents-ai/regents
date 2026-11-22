defmodule RegentsWeb.Keyfleet.KeyLinks do
  @moduledoc """
  Where a key's profile opens: its fleet's page, with the key named in the
  address. The fleet page's view (the hall, the map with `view=map`, or the
  Member List with `view=members`), the Member List's `page` and the room open
  in the hall (`room`) stay in the address beside it, so closing the profile
  leaves the page as it was.

  A key's own page and its messages are under its fleet's address, such as
  `/classic/1/keys/72`.
  """

  @kept ["page", "view", "room"]

  @doc "The fleet page with key `token_id`'s profile open, keeping what `params` kept."
  def key_path(fleet_id, token_id, params \\ %{}),
    do: fleet_path(fleet_id, kept(params) ++ [{"key", token_id}])

  @doc "Key `token_id`'s own page, where its holder manages it."
  def page_path(fleet_id, token_id),
    do: "#{Regents.Keyfleet.Fleets.path(fleet_id)}/keys/#{token_id}"

  @doc "The messages written to and from key `token_id`."
  def dms_path(fleet_id, token_id), do: "#{page_path(fleet_id, token_id)}/dms"

  @doc "The messages between key `token_id` and key `other_token_id`."
  def dm_path(fleet_id, token_id, other_token_id),
    do: "#{dms_path(fleet_id, token_id)}/#{other_token_id}"

  @doc "The fleet page with no key's profile open, keeping what `params` kept."
  def closed_path(fleet_id, params), do: fleet_path(fleet_id, kept(params))

  @doc "The fleet page's hall, its first tab."
  def hall_path(fleet_id), do: fleet_path(fleet_id, [])

  @doc "The fleet page's hall with the room at `slug` open in its middle."
  def room_path(fleet_id, slug), do: fleet_path(fleet_id, [{"room", slug}])

  @doc "The fleet page's map of Keys."
  def map_path(fleet_id), do: fleet_path(fleet_id, [{"view", "map"}])

  @doc "The fleet page's Member List: who holds its Keys."
  def members_path(fleet_id), do: fleet_path(fleet_id, [{"view", "members"}])

  @doc "Page `page` of the fleet page's Member List."
  def members_path(fleet_id, page),
    do: fleet_path(fleet_id, [{"view", "members"}, {"page", page}])

  defp kept(params), do: for(name <- @kept, is_binary(params[name]), do: {name, params[name]})

  defp fleet_path(fleet_id, []), do: Regents.Keyfleet.Fleets.path(fleet_id)

  defp fleet_path(fleet_id, query),
    do: "#{Regents.Keyfleet.Fleets.path(fleet_id)}?#{URI.encode_query(query)}"
end
