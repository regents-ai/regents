defmodule Regents.Keyfleet.Dms.Errors.SendLimitError do
  @moduledoc "Raised when a Key has sent as many direct messages as it may this hour."
  use Splode.Error, fields: [:limit, :retry_after], class: :invalid

  def message(%{limit: limit, retry_after: retry_after}),
    do: "this Key has sent #{limit} messages this hour; try again in #{retry_after} seconds"
end

defmodule Regents.Keyfleet.Dms.Errors.SameKeyError do
  @moduledoc "Raised when a Key is asked to message or block itself."
  use Splode.Error, fields: [:token_id], class: :invalid

  def message(%{token_id: token_id}), do: "Key #{token_id} cannot message or block itself"
end
