.DEFAULT_GOAL := help
.PHONY: help check check-platform platform-precommit platform-web check-required-fixes check-alignment check-cli check-siwa-latest check-contracts release deploy

help:
	@echo "make check runs every component gate side by side, each writing its output to"
	@echo "platform/_build/check/<gate>.log, then prints one line per gate and the log of"
	@echo "any that failed. A gate slower than its budget (CHECK_BUDGETS) gets a SLOW line;"
	@echo "that warns and never fails. Run check-platform, check-required-fixes, check-cli,"
	@echo "check-siwa-latest or check-contracts for one component. make release checks,"
	@echo "then builds and smoke-checks the committed tree. make deploy does the same and"
	@echo "then puts the committed HEAD on regents.sh."
# The gates share nothing they write, so they run at once. The two platform gates
# both compile for the dev environment, and Mix's build lock makes the later one wait.
CHECK_GATES := platform-precommit platform-web check-required-fixes check-cli check-siwa-latest check-contracts
CHECK_LOGS := platform/_build/check
# Each gate's budget in seconds, about 40% over its time in make check on a 16-core
# Mac (Nov 2026), and 5 s for a gate that takes a second or two. A gate over its
# budget gets a SLOW line under its own; it never fails the check.
CHECK_BUDGETS := platform-precommit:105 platform-web:75 check-required-fixes:5 check-cli:5 \
  check-siwa-latest:5 check-contracts:115
check:
	@mkdir -p $(CHECK_LOGS)
	@for gate in $(CHECK_GATES); do \
	  ( start=$$(date +%s); $(MAKE) --no-print-directory $$gate > $(CHECK_LOGS)/$$gate.log 2>&1; \
	    echo "$$? $$(( $$(date +%s) - start ))" > $(CHECK_LOGS)/$$gate.result ) & \
	done; wait
	@failed=; for gate in $(CHECK_GATES); do \
	  read code seconds < $(CHECK_LOGS)/$$gate.result; \
	  if [ "$$code" = 0 ]; then echo "$$gate: ok in $$seconds s"; \
	  else echo "$$gate: FAILED after $$seconds s"; failed="$$failed $$gate"; fi; \
	  budget=$$(printf '%s\n' $(CHECK_BUDGETS) | sed -n "s/^$$gate://p"); \
	  if [ "$$seconds" -gt "$$budget" ]; then echo "SLOW: $$gate took $$seconds s (budget $$budget s)"; fi; \
	done; \
	for gate in $$failed; do echo; echo "== $$gate ($(CHECK_LOGS)/$$gate.log)"; cat $(CHECK_LOGS)/$$gate.log; done; \
	test -z "$$failed"
check-platform: platform-precommit platform-web
platform-precommit:
	cd platform && mix precommit
platform-web:
	cd platform && mix assets.build && npm run typecheck
# Checks the site's local security/required-fixes.json registry against the
# twelve packages copied into shared/ (at the commit shared/SOURCE.json names)
# and the remaining pinned shared libraries (siwa, regent_chain, regent_ui,
# ash_postgres). No longer reaches out to ash-template on GitHub.
check-required-fixes:
	cd platform && elixir ../scripts/check-required-fixes.exs "local security/required-fixes.json" ../shared/SOURCE.json < ../security/required-fixes.json
# Prints the cross-product one-site alignment matrix across patchbay, techtree,
# autolaunch, and keyfleet (docs/one-site-standard.md).
check-alignment:
	elixir scripts/check-one-site-alignment.exs
# The command description check is regents-cli's own checker at the commit pinned
# here, run by uv straight from GitHub. Move the pin in a commit.
REGENTS_CLI_REV := 2805736810eb388ccfd7d1c97e1beca9aa4dddcd
check-cli:
	uv run --no-project --with "regents-cli[check] @ git+https://github.com/regents-ai/regents-cli@$(REGENTS_CLI_REV)" \
	  python -m regents_cli.check_commands cli/regents/commands.json platform/priv/public/openapi.json platform/priv/static/api-contract.openapiv3.yaml
# Every site is on the newest SIWA: the newest regents-cli release on PyPI (the pin
# above, the agent guide and the install lines) and the newest change to the SIWA
# library in elixir-utils. Needs `gh auth login`.
check-siwa-latest:
	scripts/check-siwa-latest.sh $(REGENTS_CLI_REV)
# The Solidity compiler takes every core it can, so it runs at a lower priority:
# beside the platform gates in make check, it gives way to them.
check-contracts:
	cd contracts && nice mise exec -- bin/gate.sh
# The release checks and builds exactly the committed tree, so every change must
# be committed first. A failing gate stops it before anything is built.
release:
	@test -z "$$(git status --porcelain)" || { echo "Commit every change first: the release checks and builds the committed tree." >&2; exit 1; }
	$(MAKE) check
	scripts/release.sh
# Deploys the committed HEAD to regents.sh, its image labelled with that commit.
# Every deploy runs the release first: the full check, then the image's own
# database commands practised on a throwaway database (scripts/release.sh).
deploy: release
	scripts/deploy.sh
