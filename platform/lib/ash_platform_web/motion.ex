defmodule AshPlatformWeb.Motion do
  @moduledoc """
  The standard motion shared with Patchbay: the version of each kind of
  movement a page uses. Presses, panels, headlines and card grids move the
  same way on every page from `assets/js/motion.ts`; a live part of a page
  names its version from here in `data-variant`.

  Parts this site has no place for yet (a note that peels, a stamp that
  thunks) keep their version here so a page that gains one moves the same
  way as Patchbay's.
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

  @doc "The standard version of one part, such as `\"list\"`."
  def standard(part), do: Map.fetch!(@standard, part)
end
