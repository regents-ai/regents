defmodule Regents.Keyfleet.Graph.Errors.UnknownFleetError do
  @moduledoc "Raised when a request names a fleet outside the catalog."
  use Splode.Error, fields: [:fleet_id], class: :invalid

  def message(%{fleet_id: fleet_id}), do: "there is no fleet #{fleet_id}"
end

defmodule Regents.Keyfleet.Graph.Errors.ComingSoonFleetError do
  @moduledoc "Raised when a request names a fleet of the catalog that hasn't opened yet."
  use Splode.Error, fields: [:fleet_id], class: :invalid

  def message(%{fleet_id: fleet_id}), do: "fleet #{fleet_id} hasn't opened yet"
end

defmodule Regents.Keyfleet.Graph.Errors.NotKeyHolderError do
  @moduledoc """
  Raised when the actor neither owns nor holds a shard of the key it acts as,
  today, nor is an agent paired with the person who owns it.
  """
  use Splode.Error, fields: [:fleet_id, :token_id], class: :forbidden

  def message(%{fleet_id: fleet_id, token_id: token_id}),
    do:
      "this wallet does not own or hold a shard of Key #{token_id} of #{fleet_id} today, " <>
        "and is not paired with the person who owns it"
end

defmodule Regents.Keyfleet.Graph.Errors.EditsRestrictedError do
  @moduledoc "Raised when a vote of the fleet has restricted the workspace edits of the key a write acts as."
  use Splode.Error, fields: [:fleet_id, :token_id], class: :forbidden

  def message(%{fleet_id: fleet_id, token_id: token_id}),
    do: "a vote of #{fleet_id} has restricted Key #{token_id}'s workspace edits"
end

defmodule Regents.Keyfleet.Graph.Errors.RefusedError do
  @moduledoc """
  The graph's own refusal of a request, with the graph's code, reason and
  details. Nothing was written.
  """
  use Splode.Error, fields: [:code, :reason, :details], class: :invalid

  def message(%{code: code, reason: reason}), do: "#{code}: #{reason}"
end

defmodule Regents.Keyfleet.Graph.Errors.UnavailableError do
  @moduledoc "Raised when the fleet's graph is not taking requests. Nothing was written."
  use Splode.Error, fields: [:fleet_id], class: :framework

  def message(%{fleet_id: fleet_id}),
    do: "the workspace of #{fleet_id} is not taking requests right now; nothing was written"
end

defmodule Regents.Keyfleet.Graph.Errors.CheckExpiredError do
  @moduledoc """
  Returned when a write's ownership check used up its time before it finished
  reading. Nothing was written.
  """
  use Splode.Error, fields: [:fleet_id], class: :framework

  def message(%{fleet_id: fleet_id}),
    do: "the ownership check for a write to #{fleet_id} ran out of time; nothing was written"
end

defmodule Regents.Keyfleet.Graph.Errors.IndeterminateError do
  @moduledoc """
  Raised when a write reached the fleet's graph but its outcome never came
  back. The write may have been applied; retrying with the same command id
  answers the original result instead of applying it twice.
  """
  use Splode.Error, fields: [:fleet_id], class: :framework

  def message(%{fleet_id: fleet_id}),
    do:
      "the workspace of #{fleet_id} did not confirm the change in time; it may have been applied"
end

defmodule Regents.Keyfleet.Graph.Errors.WriteLimitError do
  @moduledoc """
  Returned when the acting wallet has used its allowance of workspace writes
  in the fleet for now (`Regents.Keyfleet.Graph.Validations.WriteAllowance`).
  `retry_after` is the seconds until it starts again. Nothing was written.
  """
  use Splode.Error, fields: [:fleet_id, :retry_after], class: :forbidden

  def message(%{fleet_id: fleet_id, retry_after: seconds}),
    do:
      "this wallet has used its workspace writes in #{fleet_id} for now; try again in #{seconds} seconds"
end

defmodule Regents.Keyfleet.Graph.Errors.MembersOnlyError do
  @moduledoc """
  Returned when a reader of a fleet's workspace is none of its members today
  (`Regents.Keyfleet.Graph.Checks.KeyReader`), while the fleet's key ownership is
  fresh enough to say so.
  """
  use Splode.Error, fields: [:fleet_id], class: :forbidden

  def message(%{fleet_id: fleet_id}), do: "only the members of #{fleet_id} read its workspace"
end
