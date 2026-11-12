.DEFAULT_GOAL := help
.PHONY: help check check-platform platform-precommit platform-web check-required-fixes check-cli check-siwa-latest check-identity check-contracts release deploy

# Every test run on a machine uses its own databases, named from MIX_TEST_PARTITION.
REGENT_IDENTITY_TEST_DATABASE ?= regent_identity_test$(MIX_TEST_PARTITION)

help:
	@echo "make check runs every component gate side by side, each writing its output to"
	@echo "platform/_build/check/<gate>.log, then prints one line per gate and the log of"
	@echo "any that failed. Run check-platform, check-required-fixes, check-cli,"
	@echo "check-siwa-latest, check-identity or check-contracts for one component;"
	@echo "check-platform includes the headless browser checks in platform/test/browser."
	@echo "Set MIX_TEST_PARTITION (an underscore and a short id) first. make release checks,"
	@echo "then builds and smoke-checks the committed tree. make deploy puts the committed"
	@echo "HEAD on regents.sh."
# The gates share nothing they write, so they run at once. The two platform gates
# both compile for the test environment, and Mix's build lock makes the later one wait.
CHECK_GATES := platform-precommit platform-web check-required-fixes check-cli check-siwa-latest check-identity check-contracts
CHECK_LOGS := platform/_build/check
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
REGENTS_CLI_REV := fd325437e29fc6b239955e6ce946168bea2fb4ef
check-cli:
	uv run --no-project --with "regents-cli[check] @ git+https://github.com/regents-ai/regents-cli@$(REGENTS_CLI_REV)" \
	  python -m regents_cli.check_commands cli/commands.json platform/priv/public/openapi.json platform/priv/static/api-contract.openapiv3.yaml
# Every site is on the newest SIWA: the newest regents-cli release on PyPI (the pin
# above, the agent guide and the install lines) and the newest change to the SIWA
# library in elixir-utils. Needs `gh auth login`.
check-siwa-latest:
	scripts/check-siwa-latest.sh $(REGENTS_CLI_REV)
check-identity:
	psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$(REGENT_IDENTITY_TEST_DATABASE)'" | grep -q 1 || createdb $(REGENT_IDENTITY_TEST_DATABASE)
	cd identity && REGENT_IDENTITY_TEST_DATABASE=$(REGENT_IDENTITY_TEST_DATABASE) mix check
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
