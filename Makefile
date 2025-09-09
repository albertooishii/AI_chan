SHELL := /bin/bash

.PHONY: setup setup-env install-hooks deps test analyze clean run run-release install build start stop logs help coverage-report

# Default target - show help
.DEFAULT_GOAL := help

help:
	@echo "AI_chan Flutter App - Available Commands:"
	@echo ""
	@echo "📦 Setup & Dependencies:"
	@echo "  install      - Alias for setup (common convention)"
	@echo "  setup        - Full project setup (env + hooks + deps)"
	@echo "  deps         - Install Flutter dependencies"
	@echo ""
	@echo "🚀 Running the App:"
	@echo "  run          - Hot reload AUTOMÁTICO al guardar archivos .dart 🔥"
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
	@echo "  coverage-report- Generate and show coverage analysis (Dart script)"
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
	@echo "🔧 Setting up development environment..."
	@echo "📦 Installing required Ubuntu packages..."
	@if ! command -v inotifywait >/dev/null 2>&1; then \
		echo "Installing inotify-tools for hot reload..."; \
		sudo apt update && sudo apt install -y inotify-tools; \
	else \
		echo "✅ inotify-tools already installed"; \
	fi
	@if ! command -v curl >/dev/null 2>&1; then \
		echo "Installing curl..."; \
		sudo apt install -y curl; \
	else \
		echo "✅ curl already installed"; \
	fi
	@if ! command -v git >/dev/null 2>&1; then \
		echo "Installing git..."; \
		sudo apt install -y git; \
	else \
		echo "✅ git already installed"; \
	fi
	@echo "✅ System dependencies installed"
	@if [ -f scripts/setup_env.sh ]; then \
		chmod +x scripts/setup_env.sh && ./scripts/setup_env.sh; \
	else \
		echo "⚠️ scripts/setup_env.sh not found, skipping..."; \
	fi

install-hooks:
	@echo "Installing git hooks..."
	@if [ -f scripts/install-hooks.sh ]; then \
		chmod +x scripts/install-hooks.sh && ./scripts/install-hooks.sh; \
	else \
		echo "⚠️ scripts/install-hooks.sh not found, skipping..."; \
	fi

deps:
	@echo "Installing dependencies (flutter pub get)..."
	@flutter pub get

analyze:
	@flutter analyze

test:
	@flutter test --coverage


clean:
	@flutter clean
	@echo "Also cleaning temporary files..."
	@$(MAKE) clean-tmp

coverage-report:
	@echo "📊 Generating coverage report..."
	@echo "🔁 Running tests with coverage (flutter test --coverage)..."
	@flutter test --coverage || (echo "❌ Tests failed — aborting coverage report" && exit 1)
	@echo "📄 Coverage file: coverage/lcov.info"
	@if command -v genhtml >/dev/null 2>&1; then \
		echo "🖼️ Generating HTML report with genhtml..."; \
		genhtml -o coverage/html coverage/lcov.info >/dev/null 2>&1 || echo "⚠️ genhtml failed to generate HTML"; \
	else \
		echo "⚠️ genhtml not found; skipping HTML generation (install lcov to enable)."; \
	fi
	@echo "🔍 Running coverage analysis script..."
	@dart scripts/coverage_analysis.dart
	@if command -v xdg-open >/dev/null 2>&1 && [ -f coverage/html/index.html ]; then \
		echo "📂 Opening HTML report..."; \
		xdg-open coverage/html/index.html >/dev/null 2>&1 || true; \
	else \
		echo "ℹ️ To view the HTML report, open coverage/html/index.html if it exists."; \
	fi


clean-tmp:
	@echo "Cleaning temporary ai_chan folder (${TMPDIR:-/tmp}/ai_chan)"
	@chmod +x scripts/clean_tmp_ai_chan.sh 2>/dev/null || true
	@bash scripts/clean_tmp_ai_chan.sh --yes

run:
	@echo "🚀 Starting AI_chan con Hot Reload AUTOMÁTICO..."
	@./scripts/run_dev.sh

run-release:
	@echo "🚀 Starting AI_chan app in release mode..."
	@flutter run -d linux --release

stop:
	@pkill -f flutter || echo "No flutter processes found"
	@mkdir -p /tmp/ai_chan 2>/dev/null || true
	@rm -f /tmp/ai_chan/flutter_input_pipe 2>/dev/null || true

logs:
	@echo "📝 Showing debug logs (Ctrl+C to exit):"
	@if [ -f flutter_run.log ]; then \
		tail -n 200 -f flutter_run.log; \
	else \
		echo "❌ No log file found. Run 'make run' first."; \
	fi
