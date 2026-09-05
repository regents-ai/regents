import { describe } from "vitest";

// These suites bind real OS sockets/listeners (unix-domain JSON-RPC, chat relay,
// and loopback HTTP servers). A network-restricted sandbox rejects the bind with
// EPERM, which shows up as phantom failures even though the code is fine.
//
// Default behavior is to RUN everything: the gate only skips when a
// network-restricted signal is present. `REGENTS_SKIP_NETWORK_TESTS` is the
// explicit opt-out for such environments; the Codex sandbox markers are OR-ed in
// so those runs skip automatically without needing the explicit flag. CI and
// local runs leave all of these unset and therefore run the full suite.
const networkRestricted =
  process.env.REGENTS_SKIP_NETWORK_TESTS === "1" ||
  process.env.CODEX_SANDBOX_NETWORK_DISABLED === "1" ||
  process.env.CODEX_SANDBOX === "seatbelt";

const describeFn = networkRestricted ? describe.skip : describe;

const describeNetwork = Object.assign((name, fn) => describeFn(name, fn), {
  sequential: networkRestricted ? describe.skip : describe.sequential,
});

export { describeNetwork };
