defmodule AshPlatformWeb.DesignOwnershipManifestTest do
  use ExUnit.Case, async: true

  @path "priv/handoff/founder-shell-design-ownership.json"

  test "Design ownership manifest converges on the complete closed handoff" do
    manifest = @path |> File.read!() |> Jason.decode!()

    assert manifest["schema_version"] == 1

    assert manifest["post_commit_source_digest"] ==
             "ebebb7dbfd8602f6f8d302afeb05ca717bf29029"

    assert manifest["route_metadata_fields"] == [
             "path_pattern",
             "live_action",
             "parameter_schema",
             "reserved_values",
             "route_id",
             "destination",
             "app_id",
             "app_display_label",
             "page_display_label",
             "canonical_root",
             "sidebar_model",
             "header_controls",
             "search_kind",
             "background_slot",
             "content_transition_kind",
             "scroll_policy",
             "local_state"
           ]

    assert manifest["shell_assigns"] == [
             "route_spec",
             "app_targets",
             "account_control",
             "content_status",
             "presentation",
             "shell_instance"
           ]

    assert manifest["shell_slots"] == ["content"]

    assert "lib/ash_platform_web/components/shell.ex" in manifest["design_owned_paths"]

    for retired_path <- [
          "lib/ash_platform_web/components/shell/header.ex",
          "lib/ash_platform_web/components/shell/content_frame.ex"
        ] do
      refute retired_path in manifest["design_owned_paths"]
      refute retired_path in manifest["ash_owned_exclusions"]
    end

    assert manifest["theme_interface"]["choices"] == ["system", "light", "dark"]

    assert manifest["theme_interface"]["ash_owned_paths"] == [
             "assets/js/theme.ts",
             "lib/ash_platform_web/components/layouts/root.html.heex"
           ]

    assert manifest["theme_interface"]["ash_responsibilities"] == [
             "theme persistence",
             "first paint behavior"
           ]

    assert manifest["theme_interface"]["design_owned_paths"] == [
             "lib/ash_platform_web/components/shell/theme_menu.ex",
             "assets/css/components/shell.css"
           ]

    assert manifest["theme_interface"]["design_responsibility"] ==
             "presentation within the declared theme interface"

    for path <- manifest["theme_interface"]["ash_owned_paths"] do
      assert path in manifest["ash_owned_exclusions"]
      refute path in manifest["design_owned_paths"]
    end

    for path <- manifest["theme_interface"]["design_owned_paths"] do
      assert path in manifest["design_owned_paths"]
      refute path in manifest["ash_owned_exclusions"]
    end

    backgrounds = manifest["background_slots"]
    assert length(backgrounds) == 8
    assert backgrounds |> Enum.map(& &1["slot"]) |> Enum.uniq() |> length() == 8
    assert backgrounds |> Enum.map(& &1["path"]) |> Enum.uniq() |> length() == 8

    for %{"path" => path} <- backgrounds do
      assert path in manifest["design_owned_paths"]
    end

    for path <- [
          "lib/ash_platform_web/router.ex",
          "lib/ash_platform_web/live/shell_live.ex",
          "lib/ash_platform_web/route_catalog.ex",
          "assets/js/app.ts",
          "assets/js/shell_state.ts"
        ] do
      assert path in manifest["ash_owned_exclusions"]
      refute path in manifest["design_owned_paths"]
    end

    for command <- [
          "mix compile --warnings-as-errors",
          "mix test",
          "npm run typecheck",
          "npm test",
          "npm run test:budgets",
          "npm run test:browser",
          "mix hex.outdated",
          "mix hex.audit",
          "npm outdated",
          "npm audit",
          "git diff --check"
        ] do
      assert command in manifest["acceptance_commands"]
    end
  end
end
