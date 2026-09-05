import { captureOutput as captureOutputFromTestSupport } from "../../../../test-support/test-helpers.js";

export const captureOutput = captureOutputFromTestSupport;

export function parsePrintedJson(text) {
  return JSON.parse(String(text).trim());
}
