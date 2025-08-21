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
echo "🔐 Additional API Keys (optional):"
prompt_key "GEMINI_API_KEY_FALLBACK" "GEMINI_API_KEY_FALLBACK [Enter to skip]: " "" false
prompt_key "GOOGLE_CLOUD_API_KEY" "GOOGLE_CLOUD_API_KEY [Enter to skip]: " "" false

echo ""
echo "🎵 Audio/Voice Configuration:"
prompt_key "AUDIO_PROVIDER" "Audio provider (openai|gemini) [gemini]: " "gemini" false
prompt_key "AUDIO_TTS_MODE" "TTS mode (google|local) [google]: " "google" false
prompt_key "OPENAI_VOICE" "OpenAI voice [sage]: " "sage" false
prompt_key "GOOGLE_VOICE_NAME" "Google voice name [es-ES-Neural2-A]: " "es-ES-Neural2-A" false

echo ""
echo "🤖 AI Models:"
prompt_key "DEFAULT_TEXT_MODEL" "Default text model [gemini-2.5-flash]: " "gemini-2.5-flash" false
prompt_key "DEFAULT_IMAGE_MODEL" "Default image model [gpt-4.1-mini]: " "gpt-4.1-mini" false  
prompt_key "OPENAI_REALTIME_MODEL" "OpenAI realtime model [gpt-4o-realtime-preview]: " "gpt-4o-realtime-preview" false
prompt_key "GOOGLE_REALTIME_MODEL" "Google realtime model [gemini-2.5-flash]: " "gemini-2.5-flash" false

# Set default directories and log level without prompting
echo ""
echo "📁 Setting default directories and configuration..."
set_key "IMAGE_DIR_ANDROID" "/storage/emulated/0/Pictures/AI_chan"
set_key "IMAGE_DIR_IOS" "DCIM/AI_chan"
set_key "IMAGE_DIR_DESKTOP" "~/AI_chan/images"
set_key "IMAGE_DIR_WEB" "AI_chan"

set_key "AUDIO_DIR_ANDROID" "/data/user/0/com.example.ai_chan/cache"
set_key "AUDIO_DIR_IOS" "Library/Caches"
set_key "AUDIO_DIR_DESKTOP" "~/AI_chan/audio"
set_key "AUDIO_DIR_WEB" "AI_chan_audio"

set_key "CACHE_DIR_ANDROID" ""
set_key "CACHE_DIR_IOS" ""
set_key "CACHE_DIR_DESKTOP" "~/AI_chan/cache"
set_key "CACHE_DIR_WEB" "AI_chan_cache"

set_key "APP_LOG_LEVEL" "debug"

# Show summary (mask keys partially)
echo ""
echo "✅ Environment setup completed!"
echo ""
echo "🔐 API Keys:"
for k in GEMINI_API_KEY GEMINI_API_KEY_FALLBACK OPENAI_API_KEY GOOGLE_CLOUD_API_KEY; do
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
echo "🤖 Models & Audio configured with your preferences"
echo "📁 Default directories set for all platforms" 
echo "📝 Log level: debug"

echo ""

echo "Run './scripts/setup.sh' next to install dependencies and hooks, or use 'make setup' from repo root."
