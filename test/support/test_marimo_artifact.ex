defmodule AshPlatform.TestMarimoArtifact do
  @moduledoc false

  @marimo_version "0.23.14"
  @source Path.expand("fixtures/marimo_browser_notebook.py", __DIR__)
  @notebooks_root Path.expand("../../priv/static/notebooks", __DIR__)
  @build_dir Path.join(@notebooks_root, ".browser-notebook-build")

  def artifact do
    export!()

    source_hash = @source |> File.read!() |> sha256()
    manifest_json = manifest_json(@build_dir, source_hash)
    payload_hash = sha256(manifest_json)
    final_dir = Path.join(@notebooks_root, hash_hex(payload_hash))

    File.rm_rf!(final_dir)
    File.rename!(@build_dir, final_dir)

    %{
      source_hash: source_hash,
      payload_hash: payload_hash,
      manifest_json: manifest_json,
      marimo_version: @marimo_version,
      run_url: "http://127.0.0.1:4003/#{hash_hex(payload_hash)}/index.html",
      allowed_assets: [
        "https://cdn.jsdelivr.net",
        "https://wasm.marimo.app",
        "https://files.pythonhosted.org"
      ]
    }
  end

  defp export! do
    File.rm_rf!(@build_dir)
    File.mkdir_p!(@notebooks_root)

    Application.fetch_env!(:ash_platform, :marimo_exporter).export(
      @source,
      @build_dir,
      @marimo_version
    )

    unless File.regular?(Path.join(@build_dir, "index.html")) do
      raise "Marimo export did not produce index.html"
    end
  end

  defp manifest_json(directory, source_hash) do
    files =
      directory
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn path ->
        %{
          "path" => Path.relative_to(path, directory),
          "sha256" => path |> File.read!() |> sha256()
        }
      end)
      |> Enum.sort_by(& &1["path"])

    Jason.encode!(%{
      "schema_version" => 1,
      "runtime" => "pyodide",
      "marimo_version" => @marimo_version,
      "source_hash" => source_hash,
      "files" => files
    })
  end

  defp hash_hex("sha256:" <> hex), do: hex

  defp sha256(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end
end

defmodule AshPlatform.TestMarimoArtifact.UvxExporter do
  @moduledoc false

  def export(source, build_dir, marimo_version) do
    uvx = System.find_executable("uvx") || raise "uvx is required for the Marimo browser proof"

    args = [
      "--from",
      "marimo==#{marimo_version}",
      "marimo",
      "export",
      "html-wasm",
      source,
      "-o",
      build_dir,
      "--mode",
      "run",
      "--no-show-code"
    ]

    case System.cmd(uvx, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "Marimo export failed (#{status}): #{output}"
    end
  end
end
