# Regents platform

This is the Phoenix/Ash component of the Regents monorepo. Run Mix and npm here.
`lib/ash_platform/` owns domains; `lib/ash_platform_web/` owns routes and LiveViews.
`contracts/` here contains runtime API/ABI/manifests; Solidity lives in the monorepo's
root `contracts/`. Keep internal OTP/release names stable during layout changes.

Follow the root instructions and Control's `regent-workflow`. Use the ticket's
acceptance and applicable focused checks. Browser fixtures belong to the prepared
local database. Shared dependencies resolve through `REGENT_DEPS_ROOT`.
