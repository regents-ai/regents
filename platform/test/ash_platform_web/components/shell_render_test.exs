defmodule AshPlatformWeb.Components.ShellRenderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AshPlatformWeb.Components.Background

  test "the retained home background is decorative and hidden from assistive technology" do
    html = render_component(&Background.background/1, slot: :home)
    assert html =~ ~s(data-background-slot="home")
    assert html =~ "/images/backgrounds/home.svg"
    assert html =~ ~s(aria-hidden="true")
    refute html =~ "<img"
    refute html =~ "role="
  end

  test "omits retired and invalid background slots without reflecting them into markup" do
    for slot <- [
          :formation,
          :autolaunch,
          :regent_record,
          :regents_labs,
          :not_a_background,
          "<script>alert(1)</script>",
          nil,
          %{slot: :home}
        ] do
      assert render_component(&Background.background/1, slot: slot) == ""
    end
  end
end
