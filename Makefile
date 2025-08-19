SHELL := /bin/bash

.PHONY: setup setup-env install-hooks deps test analyze clean

setup: setup-env install-hooks deps
	@echo "Project setup complete. Run 'flutter run' to start."

setup-env:
	@echo "Running interactive environment setup..."
	@chmod +x scripts/setup_env.sh
	@./scripts/setup_env.sh

install-hooks:
	@echo "Installing git hooks..."
	@chmod +x scripts/install-hooks.sh
	@./scripts/install-hooks.sh

deps:
	@echo "Installing dependencies (flutter pub get)..."
	@flutter pub get

analyze:
	@flutter analyze

test:
	@flutter test --coverage

clean:
	@flutter clean
