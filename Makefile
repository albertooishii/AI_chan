SHELL := /bin/bash

.PHONY: setup setup-env install-hooks deps test analyze clean run run-release install build start stop logs help

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
	@echo ""
	@echo "🔧 Advanced Setup:"
	@echo "  setup-env    - Interactive environment setup"
	@echo "  install-hooks- Install git pre-commit hooks"
	@echo ""
	@echo "⚙️ Configuration:"
	@echo "  Set OPENAI_TTS_MODEL / OPENAI_STT_MODEL in your .env to choose OpenAI TTS/STT models used by the app (recommended: gpt-4o-mini-tts / gpt-4o-mini-transcribe)."
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
