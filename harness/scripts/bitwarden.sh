#!/bin/sh

set -o errexit
set -o nounset

BWS_VERSION="2.0.0"

read_token() {
  # Check if BWS_ACCESS_TOKEN is set and not empty
  if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
    printf "Please enter Bitwarden Secrets token: " >&2
    read -r -s BWS_ACCESS_TOKEN || true
    echo >&2

    # Verify it's not still empty after input
    if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
      echo "Error: BWS_ACCESS_TOKEN cannot be empty. Exiting." >&2
      exit 1
    fi
  fi

  # Make it visible to the bws subprocess without passing it as a CLI argument
  # (CLI args are visible to other users on the host via `ps`/`/proc`).
  export BWS_ACCESS_TOKEN

  # Return the token value
  printf "%s" "$BWS_ACCESS_TOKEN"
}

verify_bws_checksum() {
  local zip_path="$1"
  local zip_name="$2"
  local checksums_url="$3"
  local checksums_path="/tmp/bws-checksums.txt"

  echo "Verifying checksum for ${zip_name}..." >&2
  curl -fsSL "$checksums_url" -o "$checksums_path"

  local expected_line
  expected_line="$(grep "  ${zip_name}\$" "$checksums_path" || true)"
  if [ -z "$expected_line" ]; then
    echo "Error: no checksum entry found for ${zip_name} in ${checksums_url}" >&2
    exit 1
  fi

  if command -v sha256sum >/dev/null; then
    (cd "$(dirname "$zip_path")" && echo "$expected_line" | sha256sum -c -)
  else
    local expected_hash actual_hash
    expected_hash="$(echo "$expected_line" | awk '{print $1}')"
    actual_hash="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
    if [ "$expected_hash" != "$actual_hash" ]; then
      echo "Error: checksum mismatch for ${zip_name} (expected ${expected_hash}, got ${actual_hash})" >&2
      exit 1
    fi
  fi
  echo "Checksum OK" >&2
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

    local zip_name="bws-${BWS_ARCH}-${BWS_VERSION}.zip"
    local release_base="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${BWS_VERSION}"

    echo "Downloading bws for ${OS}/${ARCH} (${BWS_ARCH})..." >&2
    curl -fsSL "${release_base}/${zip_name}" -o "/tmp/${zip_name}"
    verify_bws_checksum "/tmp/${zip_name}" "$zip_name" "${release_base}/bws-sha256-checksums-${BWS_VERSION}.txt"
    unzip -o "/tmp/${zip_name}" -d "$BIN_DIR/"
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
  local server_url="$1"
  local project_id="$2"
  # Relies on BWS_ACCESS_TOKEN being exported in the environment (see read_token);
  # avoid --access-token so the token doesn't show up in `ps`/`/proc`.
  bws secret list "$project_id" --server-url "$server_url" -o env
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
  local server_url="$1"
  local project_id="$2"
  local secret_name="$3"

  if [ -z "$project_id" ]; then
    echo "Error: project_id is required" >&2
    exit 1
  fi
  if [ -z "$secret_name" ]; then
    echo "Error: secret_name is required" >&2
    exit 1
  fi

  read_token >/dev/null
  setup_bws_tool >&2

  echo "Fetching secret: ${secret_name}..." >&2

  local all_secrets
  all_secrets="$(fetch_all_secrets_as_env "$server_url" "$project_id")"
  local secret_line
  secret_line=$(echo "$all_secrets" | find_secret_line_by_name "$secret_name") || true

  if [ -z "$secret_line" ]; then
    echo "Secret '${secret_name}' not found in project '${project_id}'." >&2
    return 1
  fi

  local secret_value
  secret_value="$(echo "$secret_line" | extract_value_after_equals | remove_surrounding_quotes)"

  echo "$secret_value"
}

download_secret_by_id() {
  local server_url="$1"
  local project_id="$2"
  local secret_id="$3"

  if [ -z "$project_id" ]; then
    echo "Error: project_id is required" >&2
    exit 1
  fi
  if [ -z "$secret_id" ]; then
    echo "Error: secret_id is required" >&2
    exit 1
  fi

  read_token >/dev/null
  setup_bws_tool >&2

  echo "Fetching secret by ID: ${secret_id}..." >&2

  # Captured as a plain assignment (not combined with `local`) so that
  # bws's exit status is preserved and errexit catches a failure, without
  # depending on pipefail support in the running shell.
  local raw_secret
  raw_secret="$(bws secret get "$secret_id" --server-url "$server_url" -o env)"
  printf '%s' "$raw_secret" | extract_value_after_equals | remove_surrounding_quotes
}

download_all_secrets() {
  local server_url="$1"
  local project_id="$2"
  local output_file="$3"
  local append_mode="${4:-false}"

  if [ -z "$project_id" ]; then
    echo "Error: project_id is required" >&2
    exit 1
  fi
  if [ -z "$output_file" ]; then
    echo "Error: output_file is required" >&2
    exit 1
  fi

  read_token >/dev/null
  setup_bws_tool >&2

  echo "Fetching all secrets for project: ${project_id}..." >&2
  if [ "$append_mode" = "true" ]; then
    fetch_all_secrets_as_env "$server_url" "$project_id" >> "$output_file"
  else
    fetch_all_secrets_as_env "$server_url" "$project_id" > "$output_file"
  fi

  # Verify that the output file has at least one line with actual content
  if [ ! -s "$output_file" ] || ! grep -q '[^[:space:]]' "$output_file" 2>/dev/null; then
    echo "Error: No secrets were written to ${output_file}. The file is empty or contains only whitespace." >&2
    exit 1
  fi

  echo "Secrets saved to ${output_file}" >&2
}

# Main entry point for CLI usage
main() {
  if [ "$#" -eq 0 ]; then
    set -- ""
  fi

  local command="$1"
  shift || true

  case "$command" in
    read-token)
      read_token
      ;;
    download-secret)
      if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
        echo "Usage: $0 download-secret <server_url> <project_id> <secret_name>"
        echo "Example: $0 download-secret https://vault.teufelhome.com xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx MY_API_KEY"
        exit 1
      fi
      download_secret "$1" "$2" "$3"
      ;;
    download-secret-by-id)
      if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
        echo "Usage: $0 download-secret-by-id <server_url> <project_id> <secret_id>"
        echo "Example: $0 download-secret-by-id https://vault.teufelhome.com xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        exit 1
      fi
      download_secret_by_id "$1" "$2" "$3"
      ;;
    download-all-secrets)
      if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
        echo "Usage: $0 download-all-secrets <server_url> <project_id> <output_file> [append_mode]"
        echo "Example: $0 download-all-secrets https://vault.teufelhome.com xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /secrets/.env_secrets"
        echo "Example: $0 download-all-secrets https://vault.teufelhome.com xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /secrets/.env_secrets true"
        exit 1
      fi
      download_all_secrets "$1" "$2" "$3" "${4:-false}"
      ;;
    *)
      echo "Usage: $0 <command> [arguments]"
      echo ""
      echo "Commands:"
      echo "  read-token                               Prompt for and return the Bitwarden Secrets token"
      echo "  download-secret <server_url> <project_id> <secret_name>       Download a specific secret by name"
      echo "  download-all-secrets <server_url> <project_id> <output_file> [append_mode]  Download all secrets from a project to a file (append_mode: true|false, default: false)"
      echo ""
      echo "Environment Variables:"
      echo "  BWS_ACCESS_TOKEN - Bitwarden Secrets Manager access token (will prompt if not set)"
      exit 1
      ;;
  esac
}

# Execute main with all arguments
main "$@"
