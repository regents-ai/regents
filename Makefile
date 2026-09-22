.DEFAULT_GOAL := help
.PHONY: help check check-platform check-identity check-cli check-contracts

# Every test run on a machine uses its own databases, named from MIX_TEST_PARTITION.
REGENT_IDENTITY_TEST_DATABASE ?= regent_identity_test$(MIX_TEST_PARTITION)

help:
	@echo "make check runs every component gate. Run check-platform, check-identity,"
	@echo "check-cli or check-contracts for one component. Set REGENT_DEPS_ROOT and"
	@echo "MIX_TEST_PARTITION (an underscore and a short id) first."
check: check-platform check-identity check-cli check-contracts
check-platform:
	cd platform && mix precommit && mix assets.build && npm run typecheck && npm test
check-identity:
	psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$(REGENT_IDENTITY_TEST_DATABASE)'" | grep -q 1 || createdb $(REGENT_IDENTITY_TEST_DATABASE)
	cd identity && REGENT_IDENTITY_TEST_DATABASE=$(REGENT_IDENTITY_TEST_DATABASE) mix check
check-cli:
	cd cli && pnpm check:openapi && pnpm check:cli-contract && pnpm build && pnpm typecheck && pnpm test && pnpm check:pack-cli-contents && pnpm test:pack-smoke
check-contracts:
	cd contracts && bin/gate.sh
