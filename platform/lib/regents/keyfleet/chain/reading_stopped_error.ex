defmodule Regents.Keyfleet.Chain.ReadingStoppedError do
  @moduledoc """
  The chain reader is not reading a fleet and needs a person: the node serves
  another chain than the fleet's (`Regents.Keyfleet.Chain.ReadFleet`), or no node is
  named while fleets are deployed (`Regents.Keyfleet.Chain.Watch`). Until someone
  acts, the fleet's treasury, proposals and Keys stop updating.

  `report/1` saves it with the site's errors (`Regents.Alert`), so the two
  kinds of stop are two errors, each listing every occurrence with its own
  message.
  """
  defexception [:message]

  @doc """
  Saves the stop, with `message` saying which fleet and what to do. The
  caller's line places the error, so it must not be the caller's last call.
  """
  def report(message), do: Regents.Alert.report(%__MODULE__{message: message})
end
