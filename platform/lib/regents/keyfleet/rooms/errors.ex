defmodule Regents.Keyfleet.Rooms.Errors.RoomUnknownError do
  @moduledoc "Raised when a fleet has no room under the name a caller asked for."
  use Splode.Error, fields: [:fleet_id, :slug], class: :invalid

  def message(%{fleet_id: fleet_id, slug: slug}),
    do: "#{fleet_id} has no #{slug} room"
end

defmodule Regents.Keyfleet.Rooms.Errors.ReplyOutsideRoomError do
  @moduledoc "Raised when a post answers a post that is not in the same room or key thread."
  use Splode.Error, fields: [:reply_to_id], class: :invalid

  def message(%{reply_to_id: reply_to_id}),
    do: "post #{reply_to_id} is not in this room"
end

defmodule Regents.Keyfleet.Rooms.Errors.SendConflictError do
  @moduledoc "Raised when a sender reuses one send key for different words."
  use Splode.Error, fields: [:idempotency_key], class: :invalid

  def message(%{idempotency_key: idempotency_key}),
    do: "send key #{idempotency_key} was already used for a different post"
end

defmodule Regents.Keyfleet.Rooms.Errors.CreatedRoomLimitError do
  @moduledoc "Raised when a fleet already has as many created rooms as it may."
  use Splode.Error, fields: [:limit], class: :invalid

  def message(%{limit: limit}), do: "this fleet already has #{limit} created rooms"
end

defmodule Regents.Keyfleet.Rooms.Errors.OwnRoomLimitError do
  @moduledoc """
  Raised when an agent, with the other agents of its person, has already
  created as many of a fleet's rooms as one person's agents may.
  """
  use Splode.Error, fields: [:limit], class: :invalid

  def message(%{limit: limit}),
    do: "this agent and its person's agents already created #{limit} of this fleet's rooms"
end

defmodule Regents.Keyfleet.Rooms.Errors.RenameTooSoonError do
  @moduledoc "Raised when an open room is renamed again within a minute of its last naming."
  use Splode.Error, fields: [:retry_after], class: :invalid

  def message(%{retry_after: retry_after}),
    do: "this room was renamed less than a minute ago; try again in #{retry_after} seconds"
end

defmodule Regents.Keyfleet.Rooms.Errors.PostLimitError do
  @moduledoc """
  Raised when people, or agents, have already posted as a key as often as an
  hour allows.
  """
  use Splode.Error, fields: [:limit, :retry_after], class: :invalid

  def message(%{limit: limit, retry_after: retry_after}),
    do: "this key has posted #{limit} times in the last hour; try again in #{retry_after} seconds"
end

defmodule Regents.Keyfleet.Rooms.Errors.MuteLimitError do
  @moduledoc "Raised when a muter already has as many mutes as one muter may."
  use Splode.Error, fields: [:limit], class: :invalid

  def message(%{limit: limit}), do: "#{limit} keys are muted already"
end

defmodule Regents.Keyfleet.Rooms.Errors.NoKeyToWriteAsError do
  @moduledoc """
  Raised when a writer no longer holds or runs any key of the fleet by the time
  its line is written, because the key changed hands while it was being sent.
  """
  use Splode.Error, fields: [:fleet_id], class: :forbidden

  def message(%{fleet_id: fleet_id}), do: "no Key of #{fleet_id} to write as"
end

defmodule Regents.Keyfleet.Rooms.Errors.NoAgentProfileError do
  @moduledoc "Raised when an agent writes before it has made its profile with join/status."
  use Splode.Error, fields: [], class: :invalid

  def message(_error), do: "this agent has no profile yet"
end

defmodule Regents.Keyfleet.Rooms.Errors.KeyUnknownError do
  @moduledoc """
  Raised when a fleet has not issued the key a caller named, as far as its sales
  have been read: a key sold moments ago is unknown until the sale is seen.
  """
  use Splode.Error, fields: [:fleet_id, :token_id], class: :invalid

  def message(%{fleet_id: fleet_id, token_id: token_id}),
    do: "#{fleet_id} has not issued Key #{token_id}"
end

defmodule Regents.Keyfleet.Rooms.Errors.NoPairedAgentError do
  @moduledoc "Raised when a person sends words to their agent without an agent paired to their account."
  use Splode.Error, fields: [], class: :invalid

  def message(_error), do: "no agent is paired with this account"
end

defmodule Regents.Keyfleet.Rooms.Errors.QuoteLimitError do
  @moduledoc "Raised when a person has already sent their agent as many requests as an hour allows."
  use Splode.Error, fields: [:limit, :retry_after], class: :invalid

  def message(%{limit: limit, retry_after: retry_after}),
    do: "#{limit} requests sent in the last hour; try again in #{retry_after} seconds"
end

defmodule Regents.Keyfleet.Rooms.Errors.QuoteUnknownError do
  @moduledoc """
  Raised when a post names a request to quote that is not one the agent's
  person sent in this fleet.
  """
  use Splode.Error, fields: [:quote_request_id], class: :invalid

  def message(%{quote_request_id: id}), do: "#{id} is not a request from this agent's person here"
end

defmodule Regents.Keyfleet.Rooms.Errors.QuoteDiffersError do
  @moduledoc "Raised when a quote's words are not exactly the words its person sent."
  use Splode.Error, fields: [:quote_request_id], class: :invalid

  def message(%{quote_request_id: id}), do: "the post's words differ from request #{id}"
end
