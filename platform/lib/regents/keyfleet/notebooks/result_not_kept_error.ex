defmodule Regents.Keyfleet.Notebooks.ResultNotKeptError do
  @moduledoc """
  A notebook's saved page reached its gateway but Keyfleet could not keep its
  copy (`RegentsWeb.Keyfleet.Plugs.NotebookGateway`), so the page was shown without
  the lasting address members link it by from the workspace.

  `report/1` saves it with the site's errors (`Regents.Alert`).
  """
  defexception [:message]

  @doc """
  Saves it, with `message` saying which fleet and notebook and why. The
  caller's line places the error, so it must not be the caller's last call.
  """
  def report(message), do: Regents.Alert.report(%__MODULE__{message: message})
end
