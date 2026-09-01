defmodule AshPlatform.ReleasePackageTest do
  use ExUnit.Case, async: true

  @package_root Path.expand("../..", __DIR__)
  @dockerfile Path.join(@package_root, "Dockerfile")
  @dockerignore Path.join(@package_root, "Dockerfile.dockerignore")
  @fly_template Path.join(@package_root, "fly.toml")
  @context_script Path.join(@package_root, "scripts/build-release-context.sh")
  @release_commands ~w(migrate bootstrap-staging pending-migrations)

  test "PKG-IMAGE and PKG-TEMPLATE ship the release package files" do
    assert File.regular?(@dockerfile)
    assert File.regular?(@dockerignore)
    assert File.regular?(@fly_template)
    assert File.regular?(@context_script)
    assert File.stat!(@context_script).mode |> Bitwise.band(0o100) != 0
  end

  test "PKG-IMAGE ships every release command as an executable overlay" do
    for command <- @release_commands do
      path = Path.join(@package_root, "rel/overlays/bin/#{command}")

      assert File.regular?(path), "#{command} is missing from the release overlay"

      assert File.stat!(path).mode |> Bitwise.band(0o100) != 0,
             "#{command} would not ship executable"
    end
  end

  # Reading the ignore rules cannot tell you what they admit: a bare directory
  # re-include silently readmits everything beneath it. Only a real build knows,
  # so this asks one. It is tagged :external because it needs a Docker daemon.
  @tag :external
  test "PKG-CONTEXT the ignore rules admit exactly the declared package inputs" do
    context = temporary_directory("release-context")
    output = temporary_directory("release-context-out")

    # A miniature stand-in for the real parent context, holding one file for
    # every rule: package sources, the sibling Privy source, the narrow slice of
    # the RegentUI source the build compiles and styles from, the sealed offline
    # inputs, and the things that must never enter -- notebook output, host
    # build artifacts under a dependency's priv, a sibling's tests, lockfile,
    # tooling files, digested output and JavaScript, environment files, and
    # everything outside the declared allowlist. A real context carries one
    # bundler executable; the rules admit either architecture's name.
    write_files(context, [
      {"ash-platform/lib/app.ex", "defmodule App do\nend\n"},
      {"ash-platform/config/config.exs", "import Config\n"},
      {"ash-platform/assets/js/app.ts", "export const app = 1\n"},
      {"ash-platform/contracts/base-mainnet.json", "{}\n"},
      {"ash-platform/rel/overlays/bin/migrate", "#!/bin/sh\n"},
      {"ash-platform/priv/static/app.css", "body{}\n"},
      {"ash-platform/priv/static/notebooks/generated.js", "notebook output\n"},
      {"ash-platform/mix.exs", "defmodule App.MixProject do\nend\n"},
      {"ash-platform/mix.lock", "%{}\n"},
      {"ash-platform/package.json", "{}\n"},
      {"ash-platform/package-lock.json", "{}\n"},
      {"ash-platform/deps/dependency/lib/dependency.ex", "defmodule Dependency do\nend\n"},
      {"ash-platform/deps/dependency/priv/static/dependency.js", "export const dep = 1\n"},
      {"ash-platform/deps/dependency/priv/templates/generator.eex", "<%= @thing %>\n"},
      {"ash-platform/deps/dependency/priv/host_listener", "host build output\n"},
      {"ash-platform/deps/dependency/priv/nif.so", "host build output\n"},
      {"ash-platform/test/app_test.exs", "defmodule AppTest do\nend\n"},
      {"ash-platform/docs/guide.md", "# guide\n"},
      {"ash-platform/README.md", "# readme\n"},
      {"ash-platform/.env", "SECRET=nope\n"},
      {"ash-platform/.env.example", "SECRET=\n"},
      {"ash-platform/.envrc", "export SECRET=nope\n"},
      {"elixir-utils/privy/lib/privy.ex", "defmodule Privy do\nend\n"},
      {"elixir-utils/unrelated/lib/unrelated.ex", "defmodule Unrelated do\nend\n"},
      {"design-system/regent_ui/mix.exs", "defmodule RegentUi.MixProject do\nend\n"},
      {"design-system/regent_ui/lib/regent_ui.ex", "defmodule RegentUi do\nend\n"},
      {"design-system/regent_ui/assets/css/regent.css", ":root{}\n"},
      {"design-system/regent_ui/assets/js/regent.ts", "export const regent = 1\n"},
      {"design-system/regent_ui/priv/static/regent/sigil-3f9a.svg", "<svg/>\n"},
      {"design-system/regent_ui/test/regent/components_test.exs", "defmodule T do\nend\n"},
      {"design-system/regent_ui/deps/dependency/priv/nif.so", "host build output\n"},
      {"design-system/regent_ui/.claude/settings.json", "{}\n"},
      {"design-system/regent_ui/mix.lock", "%{}\n"},
      {"design-system/regent_ui/.formatter.exs", "[]\n"},
      {"design-system/unrelated/lib/unrelated.ex", "defmodule Unrelated do\nend\n"},
      {"mix-cache/archives/hex", "hex archive\n"},
      {"npm-cache/_cacache/content", "cache payload\n"},
      {"rustler-precompiled/nif.tar.gz", "precompiled artifact\n"},
      {"esbuild-linux-arm64", "bundler\n"},
      {"esbuild-linux-x64", "bundler\n"},
      {"stray.txt", "outside the allowlist\n"}
    ])

    dockerfile = Path.join(context, "context.Dockerfile")
    File.write!(dockerfile, "FROM scratch\nCOPY . /\n")
    File.cp!(@dockerignore, Path.join(context, "context.Dockerfile.dockerignore"))

    {out, status} =
      System.cmd(
        "docker",
        [
          "build",
          "--network=none",
          "--pull=false",
          "--quiet",
          "--file",
          dockerfile,
          "--output",
          "type=local,dest=#{output}",
          context
        ],
        stderr_to_stdout: true
      )

    assert status == 0, out

    assert admitted_files(output) == [
             "ash-platform/assets/js/app.ts",
             "ash-platform/config/config.exs",
             "ash-platform/contracts/base-mainnet.json",
             "ash-platform/deps/dependency/lib/dependency.ex",
             "ash-platform/deps/dependency/priv/static/dependency.js",
             "ash-platform/deps/dependency/priv/templates/generator.eex",
             "ash-platform/lib/app.ex",
             "ash-platform/mix.exs",
             "ash-platform/mix.lock",
             "ash-platform/package-lock.json",
             "ash-platform/package.json",
             "ash-platform/priv/static/app.css",
             "ash-platform/rel/overlays/bin/migrate",
             "design-system/regent_ui/assets/css/regent.css",
             "design-system/regent_ui/lib/regent_ui.ex",
             "design-system/regent_ui/mix.exs",
             "elixir-utils/privy/lib/privy.ex",
             "esbuild-linux-arm64",
             "esbuild-linux-x64",
             "mix-cache/archives/hex",
             "npm-cache/_cacache/content",
             "rustler-precompiled/nif.tar.gz"
           ]
  end

  defp temporary_directory(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ash-platform-#{prefix}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp write_files(root, entries) do
    Enum.each(entries, fn {relative, contents} ->
      path = Path.join(root, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
    end)
  end

  defp admitted_files(root) do
    root
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.sort()
  end
end
