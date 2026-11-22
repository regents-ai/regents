defmodule Regents.Keyfleet.Notebooks.RecordsDownError do
  @moduledoc """
  Keyfleet could not read or change its own records for a fleet's notebooks,
  though the hub may be answering: who holds the fleet's keys when a person
  opened them (`RegentsWeb.Keyfleet.NotebookOpenController`), or an agent's profile or
  a kept saved output at their gateway (`RegentsWeb.Keyfleet.Plugs.NotebookGateway`).
  Whoever asked was told the notebooks can't be opened or aren't answering
  right now, so until someone looks, members may not get in.

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
