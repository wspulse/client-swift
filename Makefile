.PHONY: help build test lint fmt check clean

# Default target
help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

build: ## Build the package
	@swift build

test: ## Run unit tests
	@swift test --filter WspulseClientTests

lint: ## Run SwiftLint checks
	@swiftlint lint --strict

fmt: ## Format source files with SwiftLint
	@swiftlint lint --fix --quiet

check: ## Run lint and unit tests (pre-commit gate)
	@echo "── lint ──"
	@$(MAKE) --no-print-directory lint
	@echo "── test ──"
	@$(MAKE) --no-print-directory test
	@echo "── all passed ──"

clean: ## Remove build artifacts
	@swift package clean
