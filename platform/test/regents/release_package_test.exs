defmodule Regents.ReleasePackageTest do
  use ExUnit.Case, async: true

  @package_root Path.expand("../..", __DIR__)
  @dockerfile Path.join(@package_root, "Dockerfile")
  @dockerignore Path.join(@package_root, "Dockerfile.dockerignore")
  @fly_template Path.join(@package_root, "fly.toml")
  @fly_staging_template Path.join(@package_root, "fly.staging.toml")
  @release_commands ~w(migrate bootstrap-staging pending-migrations)

  test "PKG-IMAGE and PKG-TEMPLATE ship the release package files" do
    assert File.regular?(@dockerfile)
    assert File.regular?(@dockerignore)
    assert File.regular?(@fly_template)
    assert File.regular?(@fly_staging_template)
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

    # A miniature stand-in for the repository checkout the release builds from,
    # holding one file for every rule: package sources, the blog content, the
    # identity library, and the things that must never enter -- identity's own
    # build output and dependencies, tests, docs, environment files and
    # everything outside the declared allowlist.
    write_files(context, [
      {"platform/lib/app.ex", "defmodule App do\nend\n"},
      {"platform/config/config.exs", "import Config\n"},
      {"platform/assets/js/app.ts", "export const app = 1\n"},
      {"platform/contracts/base-mainnet.json", "{}\n"},
      {"platform/rel/overlays/bin/migrate", "#!/bin/sh\n"},
      {"platform/priv/static/app.css", "body{}\n"},
      {"platform/mix.exs", "defmodule App.MixProject do\nend\n"},
      {"platform/mix.lock", "%{}\n"},
      {"platform/package.json", "{}\n"},
      {"platform/package-lock.json", "{}\n"},
      {"platform/deps/dependency/lib/dependency.ex", "defmodule Dependency do\nend\n"},
      {"platform/test/app_test.exs", "defmodule AppTest do\nend\n"},
      {"platform/docs/guide.md", "# guide\n"},
      {"platform/README.md", "# readme\n"},
      {"platform/.env", "SECRET=nope\n"},
      {"platform/.env.example", "SECRET=\n"},
      {"platform/.env.production", "SECRET=nope\n"},
      {"platform/.envrc", "export SECRET=nope\n"},
      {"platform/config/.env", "SECRET=nope\n"},
      {"blog/posts/first.md", "# first\n"},
      {"identity/mix.exs", "defmodule RegentIdentity.MixProject do\nend\n"},
      {"identity/lib/regent_identity.ex", "defmodule RegentIdentity do\nend\n"},
      {"identity/.env", "SECRET=nope\n"},
      {"identity/_build/dev/lib/app.beam", "host build output\n"},
      {"identity/deps/dependency/lib/dependency.ex", "defmodule Dependency do\nend\n"},
      {"contracts/src/Token.sol", "contract Token {}\n"},
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
             "blog/posts/first.md",
             "identity/lib/regent_identity.ex",
             "identity/mix.exs",
             "platform/assets/js/app.ts",
             "platform/config/config.exs",
             "platform/contracts/base-mainnet.json",
             "platform/lib/app.ex",
             "platform/mix.exs",
             "platform/mix.lock",
             "platform/package-lock.json",
             "platform/package.json",
             "platform/priv/static/app.css",
             "platform/rel/overlays/bin/migrate"
           ]
  end

  defp temporary_directory(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "platform-#{prefix}-#{System.unique_integer([:positive])}"
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
