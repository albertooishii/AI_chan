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
  local hidden="$4"

  if [ "$hidden" = "true" ]; then
    read -s -p "$prompt_text" value
    echo
  else
    read -p "$prompt_text" value
  fi
  value=${value:-$default}
  if [ -n "$value" ]; then
    set_key "$key" "$value"
    echo "Set $key"
  fi
}

# Ask for main API keys
prompt_key "GEMINI_API_KEY" "GEMINI_API_KEY (press Enter to leave empty): " ""
prompt_key "GEMINI_API_KEY_FALLBACK" "GEMINI_API_KEY_FALLBACK (optional): " ""
prompt_key "OPENAI_API_KEY" "OPENAI_API_KEY (press Enter to leave empty): " "" true

# Confirm default models if not set
if ! grep -qE "^DEFAULT_TEXT_MODEL=" "$ENV_FILE"; then
  set_key "DEFAULT_TEXT_MODEL" "gemini-2.5-flash"
fi
if ! grep -qE "^DEFAULT_IMAGE_MODEL=" "$ENV_FILE"; then
  set_key "DEFAULT_IMAGE_MODEL" "gpt-4.1-mini"
fi

# Show summary (mask keys partially)
echo "\nCreated/updated .env with the following keys:"
for k in GEMINI_API_KEY GEMINI_API_KEY_FALLBACK OPENAI_API_KEY DEFAULT_TEXT_MODEL DEFAULT_IMAGE_MODEL; do
  if grep -qE "^${k}=" "$ENV_FILE"; then
    v=$(grep -E "^${k}=" "$ENV_FILE" | sed -E "s/^${k}=(.*)$/\1/")
    if [[ "$k" =~ _KEY ]]; then
      # mask the key
      if [ -z "$v" ]; then
        echo "$k = <empty>"
      else
        echo "$k = ${v:0:4}...${v: -4}" || true
      fi
    else
      echo "$k = $v"
    fi
  else
    echo "$k = <not set>"
  fi
done

echo "\nRun './scripts/setup.sh' next to install dependencies and hooks, or use 'make setup' from repo root."
