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

  @background_dir Application.app_dir(:ash_platform, "priv/static/images/backgrounds")
  @root_template Path.expand(
                   "../../../lib/ash_platform_web/components/layouts/root.html.heex",
                   __DIR__
                 )
  @app_css Path.expand("../../../assets/css/app.css", __DIR__)
  @material_css Path.expand("../../../assets/css/tokens/material.css", __DIR__)
  @root_tokens_css Path.expand("../../../assets/css/tokens/root.css", __DIR__)
  @shell_css Path.expand("../../../assets/css/components/shell.css", __DIR__)

  test "[U2][U3] seeds branding and the saved theme from the server, not from script" do
    root = File.read!(@root_template)

    assert root =~ ~s(data-brand={)
    assert root =~ ~s(<% theme = if @conn.request_path == "/", do: "dark", else: @theme %>)
    assert root =~ ~s(data-theme={theme})
    assert root =~ ~s(<meta name="color-scheme" content={theme} />)
  end

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

  test "[U4] the mat guide follows the brand while the shell stands on one stated palette" do
    app = File.read!(@app_css)
    material = File.read!(@material_css)
    shell = File.read!(@shell_css)
    tokens = File.read!(@root_tokens_css)

    assert material =~ "--shell-background-ground: var(--color-bg)"
    assert material =~ "--material-fill: var(--glass-panel-bg)"
    assert material =~ "--material-stroke: var(--glass-panel-border)"
    assert material =~ "--material-blur: var(--glass-blur)"
    assert material =~ "--material-shadow: var(--glass-panel-shadow)"
    assert shell =~ "mask: var(--shell-background-mask) center / cover no-repeat"

    assert shell =~ "--shell-background-guide: var(--color-accent)"
    assert shell =~ "--shell-background-guide: var(--product-formation)"
    assert shell =~ "--shell-background-guide: var(--brand-accent)"

    assert app =~ "background: var(--color-surface-elevated, Canvas)"
    assert app =~ "color: var(--color-fg, CanvasText)"
    assert app =~ "outline: 3px solid var(--color-accent, AccentColor)"

    # The marketing palette is stated once, in the token file, and every other
    # shell stylesheet names a token rather than a color of its own.
    for stylesheet <- [app, material, shell] do
      refute stylesheet =~ ~r/#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?|oklch|oklab)\(\s*[.\d]/
    end

    assert tokens =~ "--ash-ground: light-dark(oklch(97% 0 0), oklch(14.5% 0 0))"
    assert tokens =~ "--ash-ink: light-dark(oklch(14.5% 0 0), oklch(97% 0 0))"
    refute shell =~ "prefers-color-scheme"
  end

  test "[U1][U4] the shell is square, token-backed, and moves only where the switch does" do
    material = File.read!(@material_css)
    shell = File.read!(@shell_css)

    assert material =~ "--material-radius: 4px"

    assert shell =~ "background: var(--ash-ground)"
    assert shell =~ "border: 1px solid var(--ash-line)"

    # The theme switch's cube is the shell's only moving part, and it stops when
    # the reader asks for less motion.
    assert shell =~ "animation: theme-cube-spin 14s linear infinite"
    assert shell =~ "@media (prefers-reduced-motion: reduce)"
    refute shell =~ ~r/transition:\s*all/
  end
end
