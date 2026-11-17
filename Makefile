.DEFAULT_GOAL := help
.PHONY: help check check-platform platform-precommit platform-web check-required-fixes check-cli check-siwa-latest check-contracts release deploy

help:
	@echo "make check runs every component gate side by side, each writing its output to"
	@echo "platform/_build/check/<gate>.log, then prints one line per gate and the log of"
	@echo "any that failed. A gate slower than its budget (CHECK_BUDGETS) gets a SLOW line;"
	@echo "that warns and never fails. Run check-platform, check-required-fixes, check-cli,"
	@echo "check-siwa-latest or check-contracts for one component; check-platform includes"
	@echo "the browser walk in platform/test/browser, one headless browser per three cores."
	@echo "Set MIX_TEST_PARTITION (an underscore and a short id) first. make release checks,"
	@echo "then builds and smoke-checks the committed tree. make deploy puts the committed"
	@echo "HEAD on regents.sh."
# The gates share nothing they write, so they run at once. The two platform gates
# both compile for the test environment, and Mix's build lock makes the later one wait.
CHECK_GATES := platform-precommit platform-web check-required-fixes check-cli check-siwa-latest check-contracts
CHECK_LOGS := platform/_build/check
# Each gate's budget in seconds, about 40% over its time in make check on a 16-core
# Mac (Nov 2026), and 5 s for a gate that takes a second or two. A gate over its
# budget gets a SLOW line under its own; it never fails the check.
CHECK_BUDGETS := platform-precommit:105 platform-web:75 check-required-fixes:5 check-cli:5 \
  check-siwa-latest:5 check-contracts:365
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
	cd platform && mix assets.build && npm run typecheck && npm test && npx playwright test
# Every site runs the same check against ash-template's current main branch, so a
# newly published required fix reaches every site's next gate. Needs `gh auth login`.
TEMPLATE := repos/regents-ai/ash-template
check-required-fixes:
	cd platform && mkdir -p _build && rev=$$(gh api $(TEMPLATE)/commits/main --jq .sha) \
	&& gh api -H "Accept: application/vnd.github.raw" "$(TEMPLATE)/contents/platform/scripts/check_required_fixes.exs?ref=$$rev" > _build/check_required_fixes.exs \
	&& gh api -H "Accept: application/vnd.github.raw" "$(TEMPLATE)/contents/security/required-fixes.json?ref=$$rev" > _build/required-fixes.json \
	&& elixir _build/check_required_fixes.exs "ash-template $$rev" < _build/required-fixes.json
# The command description check is regents-cli's own checker at the commit pinned
# here, run by uv straight from GitHub. Move the pin in a commit.
REGENTS_CLI_REV := 2e8b98c7a4dd24a8751c4dfe9979ae7902f7bd06
check-cli:
	uv run --no-project --with "regents-cli[check] @ git+https://github.com/regents-ai/regents-cli@$(REGENTS_CLI_REV)" \
	  python -m regents_cli.check_commands cli/commands.json platform/priv/public/openapi.json platform/priv/static/api-contract.openapiv3.yaml
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
deploy:
	@test -z "$$(git status --porcelain --untracked-files=no)" || { echo "Commit every change first: the deploy builds the committed tree." >&2; exit 1; }
	scripts/deploy.sh
