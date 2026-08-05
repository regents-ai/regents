defmodule AshPlatform.TestMarimoArtifactTest do
  use ExUnit.Case, async: false

  alias AshPlatform.TestMarimoArtifact

  defmodule ExporterStub do
    def export(source, build_dir, marimo_version) do
      send(self(), {:marimo_export, source, build_dir, marimo_version})
      File.mkdir_p!(build_dir)
      File.write!(Path.join(build_dir, "index.html"), "<html>mock export</html>")
      :ok
    end
  end

  setup do
    previous_exporter = Application.fetch_env!(:ash_platform, :marimo_exporter)
    Application.put_env(:ash_platform, :marimo_exporter, ExporterStub)

    on_exit(fn -> Application.put_env(:ash_platform, :marimo_exporter, previous_exporter) end)
    :ok
  end

  test "assembles the browser artifact through the configured exporter boundary" do
    artifact = TestMarimoArtifact.artifact()

    assert_receive {:marimo_export, source, build_dir, "0.23.14"}
    assert Path.basename(source) == "marimo_browser_notebook.py"
    assert Path.basename(build_dir) == ".browser-notebook-build"
    assert artifact.marimo_version == "0.23.14"
    assert artifact.manifest_json =~ ~s("path":"index.html")
    assert artifact.payload_hash == sha256(artifact.manifest_json)
  end

  defp sha256(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end
end
