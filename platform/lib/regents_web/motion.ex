defmodule RegentsWeb.Motion do
  @moduledoc """
  The standard motion every Regent site shares: the version of each kind of
  movement the pages use, picked in the template's motion lab. Presses, panels,
  headlines and card lists move the same way on every page from
  `assets/js/motion.ts`; a live part of a page names its version from here in
  `data-variant`.

  A part this site has no place for yet (a note that peels, a stamp that
  thunks) keeps its version here, so a page that gains one moves the same way
  as every other site.
  """

  @standard %{
    "drawer" => "spring",
    "sheet" => "spring",
    "menu" => "pop",
    "note" => "peel",
    "toast" => "pop",
    "list" => "bounce",
    "count" => "roll",
    "stamp" => "thunk",
    "tabs" => "glide",
    "headline" => "rise",
    "grid" => "cascade"
  }

  @doc "Every part's standard version."
  def standard, do: @standard

  @doc "The standard version of one part, such as `\"list\"`."
  def standard(part), do: Map.fetch!(@standard, part)
end
