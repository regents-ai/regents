defmodule Regents.Autolaunch.UnavailableError do
  @moduledoc """
  The record an address names could not be read just now because the database
  could not be reached (`Regents.Autolaunch.ReadFailure`), so the site answers with
  its 503 page, which offers to try again. Any other failed read is
  `Regents.Autolaunch.ReadFailedError`, and a record that does not exist
  `RegentsWeb.NotFoundError`.
  """
  defexception message: "the record at this address could not be read just now", plug_status: 503
end
