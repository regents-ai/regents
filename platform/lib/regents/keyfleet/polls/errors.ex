defmodule Regents.Keyfleet.Polls.Errors.PollUnknownError do
  @moduledoc "Raised when a fleet has no poll with the id a caller named."
  use Splode.Error, fields: [:poll_id], class: :invalid

  def message(%{poll_id: poll_id}), do: "no poll #{poll_id} in this fleet"
end

defmodule Regents.Keyfleet.Polls.Errors.PollClosedError do
  @moduledoc "Raised when a vote arrives, or an end is asked, after the poll has closed."
  use Splode.Error, fields: [], class: :invalid

  def message(_error), do: "this poll has closed"
end

defmodule Regents.Keyfleet.Polls.Errors.PollLimitError do
  @moduledoc """
  Raised when a Key that started a poll in the last 24 hours starts another,
  with the seconds until it may.
  """
  use Splode.Error, fields: [:retry_after], class: :invalid

  def message(%{retry_after: seconds}),
    do: "this Key started a poll in the last 24 hours; it may start another in #{seconds} seconds"
end

defmodule Regents.Keyfleet.Polls.Errors.ChoiceUnknownError do
  @moduledoc "Raised when a vote names a choice its poll doesn't offer."
  use Splode.Error, fields: [:choice], class: :invalid

  def message(%{choice: choice}), do: "this poll offers no choice #{inspect(choice)}"
end

defmodule Regents.Keyfleet.Polls.Errors.VoteConflictError do
  @moduledoc "Raised when a Key that already voted in a poll sends a different choice."
  use Splode.Error, fields: [], class: :invalid

  def message(_error), do: "this Key already voted differently in this poll"
end

defmodule Regents.Keyfleet.Polls.Errors.AgentVotingOffError do
  @moduledoc """
  Raised when an agent votes with a shard of a Key whose owner has turned
  agent voting off for it (`Regents.Keyfleet.Keys.governs?/3`).
  """
  use Splode.Error, fields: [:token_id], class: :forbidden

  def message(%{token_id: token_id}),
    do: "the owner of Key #{token_id} has agent voting turned off for it"
end
