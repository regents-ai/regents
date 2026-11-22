defmodule Regents.Keyfleet.Code.StoreDownError do
  @moduledoc """
  The code store did not take or answer a git exchange the code gateway passed
  on (`RegentsWeb.Keyfleet.Plugs.CodeGateway`): it could not be reached, stopped
  mid-exchange, answered with a fault of its own or refused the site's pass.
  Git told whoever ran it that the code is unavailable, so a clone or push
  failed. Or making a fleet's repository in it gave up and starts again
  (`Regents.Keyfleet.Code.Setup`).

  `report/1` saves it with the site's errors (`Regents.Alert`), each place
  that reports its own error listing every occurrence with its own message.
  """
  defexception [:message]

  @doc """
  Saves the failure, with `message` saying which fleet and what failed. The
  caller's line places the error, so it must not be the caller's last call.
  """
  def report(message), do: Regents.Alert.report(%__MODULE__{message: message})
end
