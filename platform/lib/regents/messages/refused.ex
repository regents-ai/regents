defmodule Regents.Messages.Refused do
  @moduledoc """
  Leaving a message refused its input, named by the refusal `code` every surface
  answers with (`RegentsWeb.MessagesController` holds its words):
  `idempotency_conflict`.
  """
  use Splode.Error, fields: [:code], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
