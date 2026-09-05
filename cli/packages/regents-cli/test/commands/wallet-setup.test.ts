import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { runCliEntrypoint } from "../../src/index.js";
import { captureOutput, parsePrintedJson } from "../helpers/output.js";

const { loadConfigMock, setupMock, statusMock, awalMock } = vi.hoisted(() => ({
  loadConfigMock: vi.fn(), setupMock: vi.fn(), statusMock: vi.fn(), awalMock: vi.fn(),
}));
vi.mock("../../src/internal-runtime/index.js", async importOriginal => ({
  ...await importOriginal<typeof import("../../src/internal-runtime/index.js")>(),
  loadConfig: loadConfigMock,
  setupCoinbaseWallet: setupMock,
  coinbaseStatus: statusMock,
}));
vi.mock("../../src/internal-runtime/agentic-wallet/awal.js", () => ({ runAwalJson: awalMock }));

let tempDir = "";
const fetchMock = vi.fn();
beforeEach(() => {
  vi.clearAllMocks();
  tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-wallet-discovery-"));
  vi.stubGlobal("fetch", fetchMock);
  loadConfigMock.mockImplementation(() => { throw new Error("Discovery must not read configuration or keys"); });
});
afterEach(() => {
  vi.unstubAllGlobals();
  fs.rmSync(tempDir, { recursive: true, force: true });
});

describe("wallet provider discovery", () => {
  it.each([undefined, "external", "agentic-wallet"])("keeps %s discovery offline and leaves missing config absent", async provider => {
    const configPath = path.join(tempDir, "missing", "config.json");
    const output = await captureOutput(() => runCliEntrypoint([
      "wallet", "setup", ...(provider ? ["--provider", provider] : []), "--json", "--config", configPath,
    ]));
    expect(output.result).toBe(0);
    expect(parsePrintedJson(output.stdout)).toMatchObject({
      ok: true, provider: provider ?? null,
      setup_state: provider ? "guidance_only" : "selection_required",
      verification_state: "not_checked",
    });
    expect(fs.readdirSync(tempDir)).toEqual([]);
    expect(loadConfigMock).not.toHaveBeenCalled();
    expect(setupMock).not.toHaveBeenCalled();
    expect(statusMock).not.toHaveBeenCalled();
    expect(awalMock).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("makes every advertised guidance choice executable without provider setup", async () => {
    const discovery = await captureOutput(() => runCliEntrypoint(["wallet", "setup", "--json"]));
    const { choices } = parsePrintedJson<{ choices: Array<{ provider: string; command: string }> }>(discovery.stdout);
    for (const choice of choices.filter(item => item.provider !== "coinbase-cdp")) {
      const output = await captureOutput(() => runCliEntrypoint([...choice.command.split(" ").slice(1), "--json"]));
      expect(output.result).toBe(0);
      expect(parsePrintedJson(output.stdout)).toMatchObject({ provider: choice.provider, setup_state: "guidance_only", verification_state: "not_checked" });
    }
    expect(loadConfigMock).not.toHaveBeenCalled();
    expect(setupMock).not.toHaveBeenCalled();
    expect(awalMock).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("does not inspect an existing config or its key paths during discovery", async () => {
    const configPath = path.join(tempDir, "config.json");
    fs.writeFileSync(configPath, "intentionally invalid config; do not read");
    const output = await captureOutput(() => runCliEntrypoint(["wallet", "setup", "--json", "--config", configPath]));
    expect(output.result).toBe(0);
    expect(fs.readFileSync(configPath, "utf8")).toBe("intentionally invalid config; do not read");
    expect(loadConfigMock).not.toHaveBeenCalled();
    const payload = parsePrintedJson<{ choices: Array<{ provider: string; command: string }> }>(output.stdout);
    expect(payload.choices.map(choice => choice.provider)).toEqual(expect.arrayContaining(["local-key", "external", "agentic-wallet", "coinbase-cdp"]));
  });

  it.each([
    ["--provider"], ["--provider", "unknown"], ["--wallet", "main"],
    ["--provider", "external", "--wallet", "main"], ["--provider", "coinbase-cdp", "--wallet"],
    ["--provider", "external", "--provider", "coinbase-cdp"], ["--create"],
  ])("rejects ambiguous setup input %j before invoking anything", async (...flags) => {
    const output = await captureOutput(() => runCliEntrypoint(["wallet", "setup", ...flags, "--json"]));
    expect(output.result).toBe(2);
    expect(loadConfigMock).not.toHaveBeenCalled();
    expect(setupMock).not.toHaveBeenCalled();
    expect(awalMock).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("invokes the existing Coinbase action only after explicit provider selection", async () => {
    const config = { fixture: true };
    const configPath = path.join(tempDir, "config.json");
    const result = { ok: true, provider: "coinbase-cdp", wallet: { name: "existing", address: "0x70997970c51812dc3a010c7d01b50e0d17dc79c8" }, created: false };
    loadConfigMock.mockReturnValue(config);
    setupMock.mockResolvedValue(result);
    const output = await captureOutput(() => runCliEntrypoint([
      "wallet", "setup", "--provider", "coinbase-cdp", "--wallet", "existing", "--config", configPath, "--json",
    ]));
    expect(output.result).toBe(0);
    expect(loadConfigMock).toHaveBeenCalledWith(configPath);
    expect(setupMock).toHaveBeenCalledExactlyOnceWith(config, { walletName: "existing" });
    expect(parsePrintedJson(output.stdout)).toEqual({ ...result, next_steps: ["regents identity ensure"] });
    expect(awalMock).not.toHaveBeenCalled();
  });

  it("does not report readiness when explicit Coinbase setup fails", async () => {
    loadConfigMock.mockReturnValue({});
    setupMock.mockRejectedValue(new Error("fixture provider unavailable"));
    const output = await captureOutput(() => runCliEntrypoint(["wallet", "setup", "--provider", "coinbase-cdp", "--json"]));
    expect(output.result).not.toBe(0);
    expect(parsePrintedJson(output.stdout)).toMatchObject({ ok: false, provider: "coinbase-cdp", message: "fixture provider unavailable" });
  });
});
