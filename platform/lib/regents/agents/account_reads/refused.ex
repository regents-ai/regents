defmodule Regents.Agents.AccountReads.Refused do
  @moduledoc """
  A paired agent's read was refused: `code` is the agent API's code for it,
  `invalid_cursor` or `unavailable`, whose words are the API's
  (`RegentsWeb.AgentReadsController.refusal/1`).
  """
  use Splode.Error, fields: [:code], class: :invalid

  def message(%{code: code}), do: code
end
