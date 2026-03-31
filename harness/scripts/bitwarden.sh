#!/bin/sh

set -o errexit
set -o nounset
set -o pipefail

BWS_VERSION="2.0.0"

read_token() {
  # Check if BWS_ACCESS_TOKEN is set and not empty
  if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
    printf "Please enter Bitwarden Secrets token: " >&2
    read -r -s BWS_ACCESS_TOKEN

    # Verify it's not still empty after input
    if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
      echo "Error: BWS_ACCESS_TOKEN cannot be empty. Exiting." >&2
      exit 1
    fi
  fi

  # Return the token value
  printf "%s" "$BWS_ACCESS_TOKEN"
}

setup_bws_tool() {
  if ! command -v bws >/dev/null; then
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    # Determine installation path based on OS
    if [ "$OS" = "darwin" ]; then
      # macOS - use user-writable path
      BIN_DIR="$HOME/.local/bin"
      mkdir -p "$BIN_DIR"
    else
      # Linux (containers) - use system path
      BIN_DIR="/usr/local/bin"
    fi

    # Determine the target triple based on OS and architecture
    if [ "$OS" = "darwin" ]; then
      # macOS
      if [ "$ARCH" = "arm64" ]; then
        BWS_ARCH="aarch64-apple-darwin"
      else
        BWS_ARCH="x86_64-apple-darwin"
      fi
      # Install dependencies for macOS (if needed)
      if ! command -v curl >/dev/null || ! command -v unzip >/dev/null; then
        echo "Error: curl and unzip are required. Please install them first." >&2
        exit 1
      fi
    else
      # Linux
      if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        BWS_ARCH="aarch64-unknown-linux-musl"
      else
        BWS_ARCH="x86_64-unknown-linux-musl"
      fi
      # Install dependencies for Linux (Alpine)
      if command -v apk >/dev/null; then
        apk add --no-cache curl unzip
      fi
    fi

    echo "Downloading bws for ${OS}/${ARCH} (${BWS_ARCH})..." >&2
    curl -L "https://github.com/bitwarden/sdk-sm/releases/download/bws-v${BWS_VERSION}/bws-${BWS_ARCH}-${BWS_VERSION}.zip" -o /tmp/bws.zip
    unzip -o /tmp/bws.zip -d "$BIN_DIR/"
    chmod +x "$BIN_DIR/bws"
    echo "bws installed successfully to $BIN_DIR/bws" >&2

    # Add helpful message for macOS users if ~/.local/bin is not in PATH
    if [ "$OS" = "darwin" ]; then
      if ! echo "$PATH" | grep -q "$BIN_DIR"; then
        echo "NOTE: Add $BIN_DIR to your PATH by adding this line to your ~/.zshrc:" >&2
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
      fi
    fi
  fi
}

fetch_all_secrets_as_env() {
  local project_id="$1"
  local token="$2"
  bws secret list "$project_id" --access-token "$token" -o env
}

find_secret_line_by_name() {
  local secret_name="$1"
  grep "^${secret_name}="
}

extract_value_after_equals() {
  cut -d'=' -f2-
}

remove_surrounding_quotes() {
  sed 's/^"\(.*\)"$/\1/'
}

download_secret() {
  local project_id="$1"
  local secret_name="$2"

  if [ -z "$project_id" ]; then
    echo "Error: project_id is required" >&2
    exit 1
  fi
  if [ -z "$secret_name" ]; then
    echo "Error: secret_name is required" >&2
    exit 1
  fi

  local token="$(read_token)"
  setup_bws_tool >&2

  echo "Fetching secret: ${secret_name}..." >&2

  local all_secrets="$(fetch_all_secrets_as_env "$project_id" "$token")"
  local secret_line=$(echo "$all_secrets" | find_secret_line_by_name "$secret_name")

  if [ -z "$secret_line" ]; then
    echo "Secret '${secret_name}' not found in project '${project_id}'." >&2
    return 1
  fi

  local secret_value="$(echo "$secret_line" | extract_value_after_equals | remove_surrounding_quotes)"

  echo "$secret_value"
}

download_all_secrets() {
  local project_id="$1"
  local output_file="$2"

  if [ -z "$project_id" ]; then
    echo "Error: project_id is required" >&2
    exit 1
  fi
  if [ -z "$output_file" ]; then
    echo "Error: output_file is required" >&2
    exit 1
  fi

  local token="$(read_token)"
  setup_bws_tool >&2

  echo "Fetching all secrets for project: ${project_id}..." >&2
  fetch_all_secrets_as_env "$project_id" "$token" > "$output_file"

  # Verify that the output file has at least one line with actual content
  if [ ! -s "$output_file" ] || ! grep -q '[^[:space:]]' "$output_file" 2>/dev/null; then
    echo "Error: No secrets were written to ${output_file}. The file is empty or contains only whitespace." >&2
    exit 1
  fi

  echo "Secrets saved to ${output_file}" >&2
}

# Main entry point for CLI usage
main() {
  local command="$1"
  shift

  case "$command" in
    read-token)
      read_token
      ;;
    download-secret)
      if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: $0 download-secret <project_id> <secret_name>"
        echo "Example: $0 download-secret xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx MY_API_KEY"
        exit 1
      fi
      download_secret "$1" "$2"
      ;;
    download-all-secrets)
      if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: $0 download-all-secrets <project_id> <output_file>"
        echo "Example: $0 download-all-secrets xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /secrets/.env_secrets"
        exit 1
      fi
      download_all_secrets "$1" "$2"
      ;;
    *)
      echo "Usage: $0 <command> [arguments]"
      echo ""
      echo "Commands:"
      echo "  read-token                               Prompt for and return the Bitwarden Secrets token"
      echo "  download-secret <project_id> <secret_name>       Download a specific secret by name"
      echo "  download-all-secrets <project_id> <output_file>  Download all secrets from a project to a file"
      echo ""
      echo "Environment Variables:"
      echo "  BWS_ACCESS_TOKEN - Bitwarden Secrets Manager access token (will prompt if not set)"
      exit 1
      ;;
  esac
}

# Execute main with all arguments
main "$@"