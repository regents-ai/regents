.DEFAULT_GOAL := help
.PHONY: help check-platform check-cli check-contracts
help:
	@echo "Run check-platform, check-cli or check-contracts for the changed component."
check-platform:
	cd platform && mix precommit
check-cli:
	cd cli && pnpm check:workspace && pnpm check:openapi && pnpm check:cli-contract && pnpm build && pnpm typecheck && pnpm test
check-contracts:
	cd contracts && bin/gate.sh
