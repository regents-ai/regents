defmodule Regents.Account.Agents.Connection.Refused do
  @moduledoc """
  A connected app's identity request was refused.
  """
  use Splode.Error, fields: [:error, :retry_after, :wait], class: :forbidden

  def message(%{error: %{"message" => message}}), do: message

  def message(%{wait: seconds}) when is_integer(seconds),
    do: RegentMCPAgents.Tools.wait(seconds).error.hint

  def message(_error), do: "The identity request could not be completed."
end
