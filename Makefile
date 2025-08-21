SHELL := /bin/bash

.PHONY: setup setup-env install-hooks deps test analyze clean run run-fg run-debug run-release install build start help

# Default target - show help
help:
	@echo "AI_chan Flutter App - Available Commands:"
	@echo ""
	@echo "📦 Setup & Dependencies:"
	@echo "  install      - Alias for setup (common convention)"
	@echo "  setup        - Full project setup (env + hooks + deps)"
	@echo "  deps         - Install Flutter dependencies"
	@echo ""
	@echo "🚀 Running the App:"
	@echo "  run          - Start app in background (non-blocking) ⭐"
	@echo "  start        - Alias for run (common convention)"
	@echo "  run-fg       - Start app in foreground (blocks terminal)"
	@echo "  run-debug    - Start app with hot reload (development)"
	@echo "  run-release  - Start app in release mode (optimized)"
	@echo ""
	@echo "🔍 Development Tools:"
	@echo "  test         - Run all tests with coverage"
	@echo "  analyze      - Run Flutter analyzer"
	@echo "  build        - Alias for analyze (common convention)"
	@echo "  clean        - Clean build artifacts"
	@echo ""
	@echo "🔧 Advanced Setup:"
	@echo "  setup-env    - Interactive environment setup"
	@echo "  install-hooks- Install git pre-commit hooks"
	@echo ""
	@echo "💡 Quick start: make install && make run"

# Common alias for setup
install: setup

# Common alias for analyze
build: analyze

# Common alias for run
start: run

setup: setup-env install-hooks deps
	@echo "Project setup complete. Run 'make run' to start the app."

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

run:
	@echo "Starting AI_chan app in background..."
	@nohup flutter run -d linux > /dev/null 2>&1 &
	@echo "App started in background. Use 'pkill -f flutter' to stop."

run-fg:
	@echo "Starting AI_chan app in foreground..."
	@flutter run -d linux

run-debug:
	@echo "Starting AI_chan app in debug mode with hot reload..."
	@flutter run -d linux --debug

run-release:
	@echo "Starting AI_chan app in release mode..."
	@flutter run -d linux --release
