defmodule RegentsWeb.Keyfleet.AgentTools.Refused do
  @moduledoc """
  An agent tool's refusal, as its signed request answers it: the HTTP
  `status`, the site's refusal `body` (`RegentsWeb.Keyfleet.Refusal`) and, where the
  request sends `Retry-After`, `retry_after` in seconds. The Claude
  connector's tool answers the body as its error (`RegentsWeb.Keyfleet.ToolErrors`).
  """
  use Splode.Error, fields: [:status, :body, :retry_after], class: :invalid

  def message(%{body: %{error: %{code: code}}}), do: code
end
