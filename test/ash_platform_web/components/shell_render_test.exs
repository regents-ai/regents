defmodule AshPlatformWeb.Components.ShellRenderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AshPlatformWeb.Components.Background

  @backgrounds %{
    home: "/images/backgrounds/home.svg",
    regents_labs: "/images/backgrounds/regents_labs.svg",
    formation: "/images/backgrounds/formation.svg",
    regent_record: "/images/backgrounds/regent_record.svg",
    techtree_overview: "/images/backgrounds/techtree_overview.svg",
    techtree_node: "/images/backgrounds/techtree_node.svg",
    techtree_tree: "/images/backgrounds/techtree_tree.svg",
    autolaunch: "/images/backgrounds/autolaunch.svg"
  }

  @background_dir Path.expand("../../../priv/static/images/backgrounds", __DIR__)
  @material_css Path.expand("../../../assets/css/tokens/material.css", __DIR__)
  @shell_css Path.expand("../../../assets/css/components/shell.css", __DIR__)

  test "renders every canonical background slot as inert themed mask content" do
    for {slot, source} <- @backgrounds do
      html = render_component(&Background.background/1, slot: slot)

      assert html =~ ~s(data-background-slot="#{slot}")
      assert html =~ source
      assert html =~ "--shell-background-mask"
      assert html =~ ~s(aria-hidden="true")
      refute html =~ "<img"
      refute html =~ "role="
    end
  end

  test "omits invalid background slots without reflecting them into markup" do
    for slot <- [:not_a_background, "formation", nil, %{slot: :formation}] do
      assert render_component(&Background.background/1, slot: slot) == ""
    end
  end

  test "keeps exactly eight inert and replaceable geometry masks" do
    expected_files = @backgrounds |> Map.values() |> Enum.map(&Path.basename/1)

    assert Enum.sort(File.ls!(@background_dir)) == Enum.sort(expected_files)

    for filename <- expected_files do
      svg = File.read!(Path.join(@background_dir, filename))

      assert svg =~ "background placeholder mask"
      assert svg =~ "transparent geometry mask"
      assert svg =~ "not final founder artwork"
      assert svg =~ ~s(fill="none" stroke="black")
      refute svg =~ "prefers-color-scheme"
      refute svg =~ ~r/<script|<style|<rect/i
      refute svg =~ ~r/(?:href|src)=["'](?:https?:|data:)/i
    end
  end

  test "explicit Regent theme owns neutral grounds and all approved guide palettes" do
    material = File.read!(@material_css)
    shell = File.read!(@shell_css)

    assert material =~ "--shell-background-ground: oklch(98.5% 0 0)"
    assert material =~ ":root[data-theme=\"dark\"]"
    assert material =~ "--shell-background-ground: oklch(14.5% 0 0)"
    assert shell =~ "background: var(--shell-background-ground)"
    assert shell =~ "mask: var(--shell-background-mask) center / cover no-repeat"

    for guide <- [
          "rgb(0, 95, 146)",
          "rgb(75, 168, 224)",
          "rgb(176, 63, 0)",
          "rgb(230, 115, 57)",
          "rgb(0, 122, 58)",
          "rgb(65, 214, 134)",
          "rgb(26, 88, 143)",
          "rgb(109, 169, 231)"
        ] do
      assert shell =~ guide
    end

    refute shell =~ "prefers-color-scheme"
  end

  test "structural material is square, neutral, high opacity, and motion independent" do
    material = File.read!(@material_css)
    shell = File.read!(@shell_css)

    assert material =~ "--material-radius: 4px"
    assert material =~ "--material-focus-radius: 0"
    assert material =~ "var(--color-surface-elevated) 96%"
    assert material =~ "var(--color-surface) 91%"
    refute material =~ ~r/product-(formation|autolaunch|techtree)/

    assert shell =~ "background: var(--material-fill) padding-box"
    assert shell =~ "@media (prefers-reduced-transparency: reduce)"
    refute shell =~ ~r/\.shell-material\s*\{[^}]*transition:/s
    refute shell =~ ~r/transition:\s*all|animation:/
  end
end
