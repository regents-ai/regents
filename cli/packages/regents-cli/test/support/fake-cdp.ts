import fs from "node:fs";
import path from "node:path";

export const TEST_COINBASE_WALLET = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8";
export const TEST_COINBASE_SIGNATURE = `0x${"1".repeat(130)}`;

interface FakeCdpAccount {
  name: string;
  address: string;
}

export const writeFakeCdp = (
  dir: string,
  options?: {
    accounts?: FakeCdpAccount[];
    signature?: string;
  },
): string => {
  const accounts = options?.accounts ?? [{ name: "main", address: TEST_COINBASE_WALLET }];
  const signature = options?.signature ?? TEST_COINBASE_SIGNATURE;
  const binDir = path.join(dir, "bin");
  fs.mkdirSync(binDir, { recursive: true });
  const scriptPath = path.join(binDir, "cdp");
  fs.writeFileSync(
    scriptPath,
    `#!/bin/bash
set -euo pipefail

ACCOUNTS_JSON='${JSON.stringify(accounts)}'
SIGNATURE='${signature}'
export ACCOUNTS_JSON SIGNATURE

find_account() {
  local selector="$1"
  node -e '
const accounts = JSON.parse(process.env.ACCOUNTS_JSON);
const selector = process.argv[1];
const match = accounts.find((account) => account.name === selector || account.address.toLowerCase() === selector.toLowerCase());
if (!match) {
  process.exit(1);
}
process.stdout.write(JSON.stringify(match) + "\\n");
' "$selector"
}

if [[ "$#" -ge 4 && "$1" == "evm" && "$2" == "accounts" && "$3" == "by-name" ]]; then
  find_account "$4"
  exit 0
fi

if [[ "$#" -ge 3 && "$1" == "evm" && "$2" == "accounts" && "$3" == "list" ]]; then
  printf '{"accounts":%s}\\n' "$ACCOUNTS_JSON"
  exit 0
fi

if [[ "$#" -ge 4 && "$1" == "evm" && "$2" == "accounts" && "$3" == "create" ]]; then
  node -e '
const accounts = JSON.parse(process.env.ACCOUNTS_JSON);
const nameArg = process.argv[1] ?? "name=main";
const [, requestedName = "main"] = nameArg.split("=", 2);
const match = accounts.find((account) => account.name === requestedName);
const first = accounts[0];
process.stdout.write(JSON.stringify(match ?? { name: requestedName, address: first.address }) + "\\n");
' "$4"
  exit 0
fi

if [[ "$#" -ge 5 && "$1" == "evm" && "$2" == "accounts" && "$3" == "sign" && "$4" == "message" ]]; then
  printf '{"signature":"%s"}\\n' "$SIGNATURE"
  exit 0
fi

if [[ "$#" -ge 1 && "$1" == "mcp" ]]; then
  printf '{"ok":true}\\n'
  exit 0
fi

echo "unsupported cdp command: $*" >&2
exit 1
`,
    "utf8",
  );
  fs.chmodSync(scriptPath, 0o755);
  return binDir;
};
