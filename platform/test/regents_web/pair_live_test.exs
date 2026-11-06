defmodule RegentsWeb.PairLiveTest do
  # A pairing link's page is printed as a link and pasted to an agent, so only a
  # page on this site is taken; anything a browser could read as another site is
  # dropped and the link opens plain pairing.
  use ExUnit.Case, async: true

  alias RegentsWeb.PairLive

  test "a page on this site is where the agent starts" do
    for to <- ["/", "/stake", "/paper-pro-daily/0a1b2c3d?view=all#top"],
        do: assert(PairLive.start(%{"to" => to}) == to)
  end

  test "anything else opens plain pairing" do
    for to <- [
          "//example.com",
          "/\\example.com",
          "https://example.com/stake",
          "javascript:alert(1)",
          "stake",
          "/stake now",
          "/stake\nnow",
          "/stake\u0000",
          "",
          "/" <> String.duplicate("a", 512),
          ["/stake"]
        ],
        do: assert(PairLive.start(%{"to" => to}) == nil, inspect(to))

    assert PairLive.start(%{}) == nil
  end
end
