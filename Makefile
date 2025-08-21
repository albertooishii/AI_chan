SHELL := /bin/bash

.PHONY: setup setup-env install-hooks deps test analyze clean run run-release install build start stop logs help

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
	@echo "  run          - Complete dev environment (bg + debug + hot reload) ⭐"
	@echo "  start        - Alias for run (common convention)"
	@echo "  run-release  - Start app in release mode (optimized)"
	@echo "  stop         - Stop app"
	@echo "  logs         - View debug logs in real-time"
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

run: ## 🚀 Start development environment with colors (Ctrl+C to stop)
	@./scripts/run_dev.sh

run-release:
	@echo "🚀 Starting AI_chan app in release mode..."
	@flutter run -d linux --release

stop:
	@echo "🛑 Stopping Flutter app..."
	@pkill -f flutter || echo "No Flutter process found"

logs: ## 📝 View verbose debug logs (for troubleshooting)
	@echo "📝 Showing debug logs (Ctrl+C to exit):"
	@if [ -f flutter_run.log ]; then \
		tail -f flutter_run.log; \
	else \
		echo "❌ No log file found. Run 'make run' first."; \
	fi
