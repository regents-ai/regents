defmodule AshPlatform.LocalAcceptanceScriptsTest do
  use ExUnit.Case, async: true

  @setup_script Path.expand("bin/setup-local-acceptance")
  @reset_script Path.expand("bin/reset-local-acceptance")

  test "entry scripts are valid POSIX shell" do
    assert {_, 0} = System.cmd("sh", ["-n", @setup_script], stderr_to_stdout: true)
    assert {_, 0} = System.cmd("sh", ["-n", @reset_script], stderr_to_stdout: true)
  end

  test "setup rejects an invalid run id before invoking Mix" do
    {output, status} = System.cmd(@setup_script, ["NOT-SAFE"], stderr_to_stdout: true)

    assert status != 0
    assert output =~ "lowercase"
  end

  test "setup rejects pooled remote database configuration before invoking Mix" do
    {output, status} =
      System.cmd(@setup_script, ["safe_run"],
        env: [{"DATABASE_POOLED_URL", "postgres://remote.example/prod"}],
        stderr_to_stdout: true
      )

    assert status != 0
    assert output =~ "remote database"
  end
end
