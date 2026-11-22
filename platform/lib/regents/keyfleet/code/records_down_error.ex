defmodule Regents.Keyfleet.Code.RecordsDownError do
  @moduledoc """
  Keyfleet could not read its own records when an agent asked about a fleet's
  code (`RegentsWeb.Keyfleet.AgentCodeController`): the fleet, who holds its keys, or
  the changes sent to the code lately. The agent was told to ask again in a
  minute (`code_catching_up`), so until someone looks it gets nothing. Or the
  code gateway could not read who holds a key (`code_catching_up` again), or
  could not record a push the store took (`Regents.Keyfleet.Code.record_pushes/4`),
  which the fleet's workspace then never shows.

  `report/1` saves it with the site's errors (`Regents.Alert`), each place
  that reports its own error listing every occurrence with its own message.
  """
  defexception [:message]

  @doc """
  Saves the failure, with `message` saying which fleet and what could not be
  read. The caller's line places the error, so it must not be the caller's
  last call.
  """
  def report(message), do: Regents.Alert.report(%__MODULE__{message: message})
end
