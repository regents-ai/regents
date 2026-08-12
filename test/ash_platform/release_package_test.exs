defmodule AshPlatform.ReleasePackageTest do
  use ExUnit.Case, async: true

  @dockerfile Path.expand("../../Dockerfile", __DIR__)
  @dockerignore Path.expand("../../Dockerfile.dockerignore", __DIR__)
  @fly_template Path.expand("../../fly.toml", __DIR__)

  test "PKG-CONTEXT declares the Ash tree, exact sibling Privy source, and sealed offline inputs" do
    dockerfile = File.read!(@dockerfile)
    dockerignore = File.read!(@dockerignore)

    assert dockerfile =~ "COPY ash-platform/mix.exs ash-platform/mix.lock ./"
    assert dockerfile =~ "COPY elixir-utils/privy /workspace/elixir-utils/privy"
    assert dockerfile =~ "COPY npm-cache/_cacache /root/.npm/_cacache"
    assert dockerfile =~ "COPY rustler-precompiled /workspace/rustler-precompiled"
    assert dockerfile =~ "COPY esbuild-linux-arm64 _build/esbuild-linux-arm64"

    assert dockerignore =~ "!ash-platform/"
    assert dockerignore =~ "!elixir-utils/privy/**"
    assert dockerignore =~ "!npm-cache/**"
    assert dockerignore =~ "!rustler-precompiled/**"
    assert dockerignore =~ "!esbuild-linux-arm64"
    assert dockerignore =~ "**/.env"
    assert dockerignore =~ "**/.env.*"
    refute dockerignore =~ ~r/^!.*\.env/m
  end

  test "PKG-IMAGE uses only admitted immutable builders and produces the current release" do
    dockerfile = File.read!(@dockerfile)

    from_images =
      ~r/^FROM (\S+@sha256:[0-9a-f]{64})/m
      |> Regex.scan(dockerfile, capture: :all_but_first)
      |> List.flatten()
      |> MapSet.new()

    assert from_images ==
             MapSet.new([
               "docker.io/library/gcc@sha256:9ca91b05c7b07d2979f16413e8b2cd6ec8a7c80ffca4121ccab0aeba33f90460",
               "docker.io/hexpm/elixir@sha256:d21e3b8bab8bc2e8d51eb4bb03b1d73aad6b91c5c90b3ecc778eb5d136c2e3e6",
               "docker.io/library/node@sha256:5aea649bacdc35e8e20571131c4f3547477dfe66e677d45c005af6dbd1edfaa7"
             ])

    assert dockerfile =~ "RUN npm ci --offline --ignore-scripts --no-audit --no-fund"
    assert dockerfile =~ "RUN mix assets.deploy && mix compile && mix release"
    assert dockerfile =~ ~s(CMD ["/app/bin/ash_platform", "start"])
    refute dockerfile =~ ~r/\b(?:apt|apk|curl|wget)\b/
  end

  test "PKG-TEMPLATE is identity-free and wires only release startup, migration, and liveness" do
    template = File.read!(@fly_template)

    refute template =~ ~r/^\s*(?:app|org|primary_region)\s*=/m
    refute template =~ ~r/\b(?:secret|database|volume|certificate|dns)\b/i
    assert template =~ ~s(dockerfile = "Dockerfile")
    assert template =~ ~s(release_command = "/app/bin/migrate")
    assert template =~ "internal_port = 4000"
    assert template =~ "force_https = true"
    assert template =~ ~s(path = "/healthz")
  end
end
