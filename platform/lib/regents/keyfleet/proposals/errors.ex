defmodule Regents.Keyfleet.Proposals.Errors.WordsLimitError do
  @moduledoc """
  Raised when a person or an agent has saved proposal words as often as the
  window allows (`config :regents, :keyfleet_proposal_words_rate_limit`).
  """
  use Splode.Error, fields: [:retry_after], class: :invalid

  def message(%{retry_after: retry_after}),
    do: "proposal words were saved too often; try again in #{retry_after} seconds"
end
