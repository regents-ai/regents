defmodule Regents.Keyfleet.Notebooks.HubSilentError do
  @moduledoc """
  A fleet's notebook hub did not answer what it was asked: making a holder an
  editor (`Regents.Keyfleet.Notebooks.admit/3`), listing the sessions open in it
  (`Regents.Keyfleet.Notebooks.session_room?/2`), or a request passed on or a live
  connection opened by its gateway (`RegentsWeb.Keyfleet.Plugs.NotebookGateway`). Whoever asked was told the notebooks
  are unavailable, so until someone looks at the hub its members cannot work
  in it. A request to a hub that no connection came free for in time is
  reported where every request to a hub passes (`Regents.Keyfleet.Notebooks.hub_run/2`),
  and only there: it is that request's error, which the places above leave
  as reported. A fleet's search that the hub didn't answer, or didn't answer in
  time (`Regents.Keyfleet.Search`), answered without the fleet's notebooks.

  `report/1` saves it with the site's errors (`Regents.Alert`), each place
  that reports its own error listing every occurrence with its own message.
  """
  defexception [:message]

  @doc """
  Saves the failure, with `message` saying which fleet and what the hub said,
  and answers it. The caller's line places the error, so it must not be the
  caller's last call.
  """
  def report(message) do
    error = %__MODULE__{message: message}
    Regents.Alert.report(error)
    error
  end
end
