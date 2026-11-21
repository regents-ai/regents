defmodule Regents.Keyfleet.Seasons.Errors.SeasonUnknownError do
  @moduledoc "Raised when a fleet has no season with the number a caller named."
  use Splode.Error, fields: [:number], class: :invalid

  def message(%{number: number}), do: "this fleet has no season #{number}"
end

defmodule Regents.Keyfleet.Seasons.Errors.PicksClosedError do
  @moduledoc "Raised when a pick arrives for a season that has started."
  use Splode.Error, fields: [:number], class: :invalid

  def message(%{number: number}), do: "season #{number} has started; its picks are final"
end

defmodule Regents.Keyfleet.Seasons.Errors.ProductIneligibleError do
  @moduledoc """
  Raised when a pick names a product that may not be picked now: not on
  Coinbase as spot, quoted in US dollars and open for trading, or traded too
  little over the last 24 hours.
  """
  use Splode.Error, fields: [:product], class: :invalid

  def message(%{product: product}), do: "#{product} may not be picked now"
end

defmodule Regents.Keyfleet.Seasons.Errors.ReasonError do
  @moduledoc """
  Raised when a pick's reason breaks one of its rules
  (`Regents.Keyfleet.Seasons.Validations.Reason`). `rule` names which, and the
  message says it in the words the page and an agent's refusal show.
  """
  use Splode.Error, fields: [:rule], class: :invalid

  def message(%{rule: :plain}), do: "A reason is one line of ordinary text."

  def message(%{rule: :too_long}),
    do: "A reason is at most 500 characters, and an emoji counts as two or more."

  def message(%{rule: :blank}), do: "A reason needs at least one character that shows."

  def message(%{rule: :marks}),
    do: "A reason puts no more than six accents or other marks on one letter."
end

defmodule Regents.Keyfleet.Seasons.Errors.ProductsUnreadError do
  @moduledoc """
  Raised when a pick arrives while the products that may be picked have not
  been read from Coinbase. Nothing was written.
  """
  use Splode.Error, fields: [], class: :framework

  def message(_error),
    do: "the products that may be picked could not be read just now; nothing was written"
end
