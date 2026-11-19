defmodule RegentSprites.Error do
  @moduledoc """
  Why a call did not return a result.

  Reasons:

    * `:token_missing` — no Sprites token is configured
    * `{:sprites, status, message}` — Sprites answered with an error status, such as
      `404` for an unknown machine or `409` for a name already in use; `message` is
      Sprites' own `error` text, or `nil`
    * `{:transport, message}` — the request did not reach Sprites or timed out
    * `{:stream, message}` — a checkpoint or restore reported an error part way through
    * `:stream_incomplete` — a checkpoint or restore ended without saying it finished
    * `{:checkpoint_not_found, comment}` — no checkpoint carries the comment after it
      was made
    * `{:comment_not_unique, comment}` — more than one checkpoint carries the comment
    * `{:exit, code, stderr}` — a file read or write ended with a non-zero exit code
    * `:unexpected_response` — Sprites answered in a shape this package does not read
  """

  defexception [:reason]

  @type t :: %__MODULE__{reason: term()}

  @impl true
  def message(%__MODULE__{reason: reason}), do: describe(reason)

  defp describe(:token_missing), do: "the Sprites token is not configured"
  defp describe({:sprites, status, nil}), do: "Sprites answered #{status}"
  defp describe({:sprites, status, message}), do: "Sprites answered #{status}: #{message}"
  defp describe({:transport, message}), do: "Sprites could not be reached: #{message}"
  defp describe({:stream, message}), do: "Sprites reported an error: #{message}"
  defp describe(:stream_incomplete), do: "Sprites ended the stream without finishing"
  defp describe({:checkpoint_not_found, comment}), do: "no checkpoint has the comment #{comment}"

  defp describe({:comment_not_unique, comment}),
    do: "more than one checkpoint has the comment #{comment}"

  defp describe({:exit, code, _stderr}), do: "the command ended with exit code #{code}"
  defp describe(:unexpected_response), do: "Sprites answered in an unexpected shape"
end
