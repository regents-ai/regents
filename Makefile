.DEFAULT_GOAL := help
.PHONY: help check check-platform check-required-fixes check-identity check-payments check-agents check-contracts release

# Every test run on a machine uses its own databases, named from MIX_TEST_PARTITION.
REGENT_IDENTITY_TEST_DATABASE ?= regent_identity_test$(MIX_TEST_PARTITION)
REGENT_PAYMENTS_TEST_DATABASE := regent_payments_test$(MIX_TEST_PARTITION)
REGENT_AGENTS_TEST_DATABASE := regent_agents_test$(MIX_TEST_PARTITION)

help:
	@echo "make check runs every component gate. Run check-platform, check-required-fixes,"
	@echo "check-identity, check-payments, check-agents or check-contracts for one component. Set MIX_TEST_PARTITION"
	@echo "(an underscore and a short id) first. make release checks, then builds and"
	@echo "smoke-checks the committed tree."
check: check-platform check-required-fixes check-identity check-payments check-agents check-contracts
check-platform:
	cd platform && mix precommit && mix assets.build && npm run typecheck && npm test
# Every site runs the same check against ash-template's current main branch, so a
# newly published required fix reaches every site's next gate. Needs `gh auth login`.
TEMPLATE := repos/regents-ai/ash-template
check-required-fixes:
	cd platform && mkdir -p _build && rev=$$(gh api $(TEMPLATE)/commits/main --jq .sha) \
	&& gh api -H "Accept: application/vnd.github.raw" "$(TEMPLATE)/contents/platform/scripts/check_required_fixes.exs?ref=$$rev" > _build/check_required_fixes.exs \
	&& gh api -H "Accept: application/vnd.github.raw" "$(TEMPLATE)/contents/security/required-fixes.json?ref=$$rev" > _build/required-fixes.json \
	&& elixir _build/check_required_fixes.exs "ash-template $$rev" < _build/required-fixes.json
check-identity:
	psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$(REGENT_IDENTITY_TEST_DATABASE)'" | grep -q 1 || createdb $(REGENT_IDENTITY_TEST_DATABASE)
	cd identity && REGENT_IDENTITY_TEST_DATABASE=$(REGENT_IDENTITY_TEST_DATABASE) mix check
check-payments:
	psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$(REGENT_PAYMENTS_TEST_DATABASE)'" | grep -q 1 || createdb $(REGENT_PAYMENTS_TEST_DATABASE)
	cd payments && MIX_ENV=test mix check
check-agents:
	psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$(REGENT_AGENTS_TEST_DATABASE)'" | grep -q 1 || createdb $(REGENT_AGENTS_TEST_DATABASE)
	cd agents && MIX_ENV=test mix check
check-contracts:
	cd contracts && mise exec -- bin/gate.sh
# The release checks and builds exactly the committed tree, so every change must
# be committed first. A failing gate stops it before anything is built.
release:
	@test -z "$$(git status --porcelain)" || { echo "Commit every change first: the release checks and builds the committed tree." >&2; exit 1; }
	$(MAKE) check
	scripts/release.sh
