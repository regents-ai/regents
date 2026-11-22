defmodule Regents.Autolaunch.ReadFailedError do
  @moduledoc """
  The record an address names could not be read, for a reason other than a
  lost database connection (`Regents.Autolaunch.ReadFailure`), so the site answers
  with its plain 500 page. A lost connection is `RegentsWeb.Autolaunch.UnavailableError`
  instead, and a record that does not exist `RegentsWeb.NotFoundError`.
  """
  defexception message: "the record at this address could not be read", plug_status: 500
end
