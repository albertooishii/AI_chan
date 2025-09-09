#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE="$ROOT_DIR/.env.example"
ENV_FILE="$ROOT_DIR/.env"

echo "Interactive environment setup"

if [ -f "$ENV_FILE" ]; then
  read -p ".env already exists. Overwrite? [y/N]: " yn
  yn=${yn:-N}
  if [[ ! "$yn" =~ ^[Yy] ]]; then
    echo "Aborting. .env not modified."
    exit 0
  fi
fi

if [ -f "$EXAMPLE" ]; then
  cp "$EXAMPLE" "$ENV_FILE"
  echo "Copied .env.example to .env"
else
  echo "# Auto-generated .env" > "$ENV_FILE"
fi

# Helper to set or replace a key in .env
set_key() {
  local key="$1"
  local val="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

prompt_key() {
  local key="$1"
  local prompt_text="$2"
  local default="$3"
  local hidden="${4:-false}"

  if [ "$hidden" = "true" ]; then
    read -s -p "$prompt_text" value
    echo
  else
    read -p "$prompt_text" value
  fi
  
  # Use default if value is empty
  value=${value:-$default}
  
  # Always set the key, even if empty (for API keys that might be optional)
  set_key "$key" "$value"
  
  if [ -n "$value" ]; then
    echo "✅ Set $key"
  else
    echo "⏭️  Skipped $key (empty)"
  fi
}

# Ask for API keys (required)
echo ""
echo "🔐 API Keys (required for app to work):"
echo "   Note: API keys will be visible while typing for easier input"
prompt_key "GEMINI_API_KEY" "Enter GEMINI_API_KEY: " "" false
prompt_key "OPENAI_API_KEY" "Enter OPENAI_API_KEY: " "" false

echo ""
echo "🔐 Optional / additional API keys (press Enter to skip):"
prompt_key "GROK_API_KEY" "GROK_API_KEY [Enter to skip]: " "" false
prompt_key "GEMINI_API_KEY_FALLBACK" "GEMINI_API_KEY_FALLBACK [Enter to skip]: " "" false
prompt_key "GOOGLE_CLOUD_API_KEY" "GOOGLE_CLOUD_API_KEY [Enter to skip]: " "" false

echo ""
echo "🛠️  OAuth client IDs / secrets (optional). Secrets will be hidden while typing."
prompt_key "GOOGLE_CLIENT_ID_DESKTOP" "GOOGLE_CLIENT_ID_DESKTOP (OAuth client id para Desktop) [Enter to skip]: " "" false
prompt_key "GOOGLE_CLIENT_SECRET_DESKTOP" "GOOGLE_CLIENT_SECRET_DESKTOP (secret) [Enter to skip]: " "" true
prompt_key "GOOGLE_CLIENT_ID_ANDROID" "GOOGLE_CLIENT_ID_ANDROID (OAuth client id para Android) [Enter to skip]: " "" false
prompt_key "GOOGLE_CLIENT_ID_WEB" "GOOGLE_CLIENT_ID_WEB (OAuth client id para Web) [Enter to skip]: " "" false
prompt_key "GOOGLE_CLIENT_SECRET_WEB" "GOOGLE_CLIENT_SECRET_WEB (secret) [Enter to skip]: " "" true

echo ""
echo "🎵 Audio/Voice Configuration:"
prompt_key "AUDIO_PROVIDER" "Audio provider (openai|gemini) [gemini]: " "gemini" false
prompt_key "AUDIO_TTS_MODE" "TTS mode (google|local) [google]: " "google" false
prompt_key "OPENAI_VOICE_NAME" "OpenAI voice [marin]: " "marin" false
prompt_key "GOOGLE_VOICE_NAME" "Google voice name [es-ES-Wavenet-F]: " "es-ES-Wavenet-F" false
# The application uses OS-recommended default directories for images/audio/cache.
# We no longer write platform-specific path overrides to .env.
echo ""
echo "📁 Using OS default directories for images/audio/cache. No path overrides will be written to .env."

# Set non-path defaults
set_key "DEBUG_MODE" "basic"
# Preferred audio format for storage and STT fallbacks
set_key "PREFERRED_AUDIO_FORMAT" "mp3"
# Application name (do not prompt; use default)
set_key "APP_NAME" "AI-チャン"

# Show summary (mask keys partially)
echo ""
echo "✅ Environment setup completed!"
echo ""
echo "🔐 API Keys:"
for k in GEMINI_API_KEY GEMINI_API_KEY_FALLBACK OPENAI_API_KEY GROK_API_KEY GOOGLE_CLOUD_API_KEY GOOGLE_CLIENT_ID_DESKTOP GOOGLE_CLIENT_ID_ANDROID GOOGLE_CLIENT_ID_WEB; do
  if grep -qE "^${k}=" "$ENV_FILE"; then
    v=$(grep -E "^${k}=" "$ENV_FILE" | sed -E "s/^${k}=(.*)$/\1/")
    if [ -z "$v" ] || [ "$v" = "PUT_YOUR_GEMINI_KEY_HERE" ] || [ "$v" = "PUT_YOUR_OPENAI_KEY_HERE" ] || [ "$v" = "PUT_YOUR_GOOGLE_CLOUD_KEY_HERE" ]; then
      echo "  $k = ❌ <not configured>"
    else
      echo "  $k = ✅ ${v:0:4}...${v: -4}" || true
    fi
  fi
done

echo ""
echo "🤖 Model defaults are now configured in assets/ai_providers_config.yaml"
echo "📁 Default directories set for all platforms" 
echo "📝 Log level: debug"

echo ""

echo "Run './scripts/setup.sh' next to install dependencies and hooks, or use 'make setup' from repo root."
