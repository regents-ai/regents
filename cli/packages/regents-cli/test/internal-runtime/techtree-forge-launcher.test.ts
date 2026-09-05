import {
  chmodSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  handleTechtreeForgeFamilyShow,
  runVerifyRuntimePython,
} from "../../src/internal-runtime/handlers/techtree/forge.js";

const originalPath = process.env.PATH;
const temporaryDirectories: string[] = [];

const temporaryDirectory = (): string => {
  const directory = mkdtempSync(path.join(os.tmpdir(), "regents-forge-python-"));
  temporaryDirectories.push(directory);
  return directory;
};

const installFakePython = (directory: string, source: string): void => {
  const executable = path.join(directory, "python3");
  writeFileSync(executable, source);
  chmodSync(executable, 0o755);
};

afterEach(() => {
  if (originalPath === undefined) {
    delete process.env.PATH;
  } else {
    process.env.PATH = originalPath;
  }
  delete process.env.REGENTS_VERIFY_RUNTIME_TEST_PID_FILE;

  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("Techtree Forge Python launcher", () => {
  it("reports a missing python3 interpreter with the required remedy", async () => {
    process.env.PATH = temporaryDirectory();

    const error = await handleTechtreeForgeFamilyShow().then(
      () => undefined,
      (caught: unknown) => caught,
    );

    expect(error).toMatchObject({ code: "verify_runtime_unavailable" });
    expect(error).toBeInstanceOf(Error);
    expect((error as Error).message).toContain("python3 could not start");
    expect((error as Error).message).toContain("Install Python 3.12 or newer");
  }, 2_000);

  it("rejects a python3 interpreter older than 3.12", async () => {
    const directory = temporaryDirectory();
    installFakePython(directory, "#!/bin/sh\nprintf '3.11\\n'\n");
    process.env.PATH = directory;

    const error = await handleTechtreeForgeFamilyShow().then(
      () => undefined,
      (caught: unknown) => caught,
    );

    expect(error).toMatchObject({ code: "verify_runtime_unavailable" });
    expect((error as Error).message).toContain("python3 3.11 is too old");
    expect((error as Error).message).toContain("Install Python 3.12 or newer");
  });

  it("kills a timed-out python3 child process", async () => {
    const directory = temporaryDirectory();
    const pidFile = path.join(directory, "python.pid");
    installFakePython(
      directory,
      [
        "#!/bin/sh",
        'printf \'%s\' "$$" > "$REGENTS_VERIFY_RUNTIME_TEST_PID_FILE"',
        "while :; do :; done",
        "",
      ].join("\n"),
    );
    process.env.PATH = directory;
    process.env.REGENTS_VERIFY_RUNTIME_TEST_PID_FILE = pidFile;

    await expect(
      runVerifyRuntimePython(["-c", "ignored"], {
        runtimeDirectory: directory,
        purpose: "testing timeout cleanup",
        timeoutMs: 2_000,
      }),
    ).rejects.toMatchObject({
      code: "verify_runtime_unavailable",
      message: expect.stringContaining("timed out after 2000ms"),
    });

    await vi.waitFor(() => expect(existsSync(pidFile)).toBe(true));
    const pid = Number(readFileSync(pidFile, "utf8"));
    await vi.waitFor(
      () => expect(() => process.kill(pid, 0)).toThrow(),
      { timeout: 2_000, interval: 20 },
    );
  });

  it("kills and rejects python3 output above the shared capture limit", async () => {
    const directory = temporaryDirectory();
    installFakePython(
      directory,
      "#!/bin/sh\n/usr/bin/head -c 4194305 /dev/zero | /usr/bin/tr '\\000' x\n",
    );
    process.env.PATH = directory;

    await expect(
      runVerifyRuntimePython(["-c", "ignored"], {
        runtimeDirectory: directory,
        purpose: "testing output capture",
        timeoutMs: 5_000,
      }),
    ).rejects.toMatchObject({
      code: "verify_runtime_unavailable",
      message: expect.stringContaining("stdout exceeded 4194304 bytes"),
      details: { stream: "stdout", max_output_bytes: 4_194_304 },
    });
  });
});
