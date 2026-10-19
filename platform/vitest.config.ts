import {defineConfig} from "vitest/config"

export default defineConfig({
  test: {
    include: ["assets/test/**/*.test.ts"],
    // What a passing test prints stays hidden; a failing test shows all of it.
    silent: "passed-only",
  },
})
