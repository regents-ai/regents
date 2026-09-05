import { describe, expect, it } from "vitest";

import {
  optionalCsvFlag,
  parseOptionalNonNegativeIntegerFlag,
  parseRequiredNonNegativeIntegerFlag,
  readJsonObjectValue,
  readOptionalJsonObjectFlag,
} from "../src/command-input.js";
import { getFlag, getFlags, parseCliArgs, parseIntegerFlag } from "../src/parse.js";

describe("CLI parsing", () => {
  it("keeps empty positional arguments instead of dropping them", () => {
    const parsed = parseCliArgs(["alpha", "", "--flag", "value", "--", "", "omega"]);

    expect(parsed.positionals).toEqual(["alpha", "", "", "omega"]);
    expect(getFlag(parsed, "flag")).toBe("value");
  });

  it("rejects malformed integer flags", () => {
    expect(() => parseIntegerFlag(["--limit", "12abc"], "limit")).toThrow("invalid integer for --limit");
    expect(() => parseIntegerFlag(["--limit", "001"], "limit")).toThrow("invalid integer for --limit");
  });

  it("keeps repeated long flags in order", () => {
    const parsed = parseCliArgs(["work", "--tag", "one", "--tag=two", "--tag", "three"]);

    expect(getFlag(parsed, "tag")).toBe("three");
    expect(getFlags(parsed, "tag")).toEqual(["one", "two", "three"]);
  });

  it("parses shared JSON, CSV, and non-negative integer inputs", () => {
    const parsed = parseCliArgs([
      "work",
      "--refs",
      "{\"node\":\"node_123\"}",
      "--kind",
      "review,node",
      "--kind",
      "publish",
      "--attempt",
      "0",
    ]);

    expect(readOptionalJsonObjectFlag(parsed, "refs")).toEqual({ node: "node_123" });
    expect(optionalCsvFlag(parsed, "kind")).toEqual(["review", "node", "publish"]);
    expect(parseRequiredNonNegativeIntegerFlag(parsed, "attempt")).toBe(0);
    expect(parseOptionalNonNegativeIntegerFlag(parsed, "attempt")).toBe(0);
    expect(parseOptionalNonNegativeIntegerFlag(parsed, "missing")).toBeUndefined();
  });

  it("rejects malformed shared JSON and negative integer inputs", () => {
    expect(() => readJsonObjectValue("[]", "--refs")).toThrow("invalid --refs");
    expect(() => parseRequiredNonNegativeIntegerFlag(["--attempt", "-1"], "attempt")).toThrow(
      "invalid integer for --attempt",
    );
  });
});
