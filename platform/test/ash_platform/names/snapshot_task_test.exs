defmodule AshPlatform.Names.SnapshotTaskTest do
  use ExUnit.Case, async: false
  alias Mix.Tasks.AshPlatform.Names.VerifySnapshot

  setup do
    path =
      Path.join(System.tmp_dir!(), "claim-snapshot-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "rejects duplicate object keys at every level without revealing values", %{path: path} do
    for json <- [
          ~s({"format":1,"format":1}),
          ~s({"tables":[{"rows":[{"owner_address":"private-owner","owner_address":"other-owner"}]}]})
        ] do
      File.write!(path, json)

      error =
        assert_raise Mix.Error, fn ->
          VerifySnapshot.run(["--source", path, "--candidate", path])
        end

      assert error.message == "Duplicate JSON object keys (contents omitted)"
    end
  end

  test "malformed JSON and missing files produce redacted errors", %{path: path} do
    File.write!(path, "{private-owner")

    error =
      assert_raise Mix.Error, fn ->
        VerifySnapshot.run(["--source", path, "--candidate", path])
      end

    assert error.message == "Cannot read a valid JSON snapshot (contents omitted)"
    File.rm!(path)
    assert_raise Mix.Error, fn -> VerifySnapshot.run(["--source", path, "--candidate", path]) end
  end

  test "invalid arguments cannot start a comparison" do
    assert_raise Mix.Error, fn -> VerifySnapshot.run(["--source", "a.json"]) end

    assert_raise Mix.Error, fn ->
      VerifySnapshot.run(["--source", "a.json", "--candidate", "b.json", "--force"])
    end
  end
end
