#!/bin/sh
set -eu

TRACEO_DIST_REPO="${TRACEO_DIST_REPO:-caik13/traceo-cli-dist}"
TRACEO_DIST_BASE_URL="${TRACEO_DIST_BASE_URL:-https://raw.githubusercontent.com/$TRACEO_DIST_REPO/main}"
TRACEO_INSTALL_DIR="${TRACEO_INSTALL_DIR:-$HOME/.local/bin}"
TRACEO_NO_MODIFY_PATH="${TRACEO_NO_MODIFY_PATH:-0}"
TRACEO_VERSION="${TRACEO_VERSION:-}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

warn() {
  echo "$1" >&2
}

detect_platform() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  case "$arch" in
    x86_64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
  esac

  platform="${os}_${arch}"
  case "$platform" in
    darwin_arm64|darwin_amd64|linux_amd64)
      printf '%s\n' "$platform"
      ;;
    *)
      echo "unsupported platform: $platform" >&2
      exit 1
      ;;
  esac
}

resolve_version() {
  if [ -n "$TRACEO_VERSION" ]; then
    printf '%s\n' "${TRACEO_VERSION#v}"
    return
  fi

  curl -fsSL "$TRACEO_DIST_BASE_URL/LATEST"
}

release_base_url() {
  version=$(resolve_version)
  printf '%s/releases/v%s\n' "${TRACEO_DIST_BASE_URL%/}" "$version"
}

checksum_ok() {
  archive_name=$1
  checksums_file=$2
  checksum_line=$(grep "[[:space:]]$archive_name\$" "$checksums_file" || true)

  if [ -z "$checksum_line" ]; then
    echo "checksum entry for $archive_name not found in $checksums_file" >&2
    exit 1
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s\n' "$checksum_line" | (cd "$(dirname "$checksums_file")" && shasum -a 256 -c -)
    return
  fi

  printf '%s\n' "$checksum_line" | (cd "$(dirname "$checksums_file")" && sha256sum -c -)
}

append_path_if_needed() {
  if [ "$TRACEO_NO_MODIFY_PATH" = "1" ]; then
    return 0
  fi

  case ":$PATH:" in
    *":$TRACEO_INSTALL_DIR:"*)
      return 0
      ;;
  esac

  shell_name=$(basename "${SHELL:-}")
  rc_file="$HOME/.profile"

  case "$shell_name" in
    zsh) rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bash_profile" ;;
  esac

  line="export PATH=\"$TRACEO_INSTALL_DIR:\$PATH\""

  if ! mkdir -p "$(dirname "$rc_file")"; then
    warn "traceo installed, but could not prepare $(dirname "$rc_file") for PATH update."
    warn "Add $TRACEO_INSTALL_DIR to PATH manually."
    return 0
  fi

  if ! touch "$rc_file"; then
    warn "traceo installed, but could not update $rc_file."
    warn "Add $TRACEO_INSTALL_DIR to PATH manually."
    return 0
  fi

  if ! grep -F "$line" "$rc_file" >/dev/null 2>&1; then
    if ! printf '\n%s\n' "$line" >>"$rc_file"; then
      warn "traceo installed, but could not append PATH to $rc_file."
      warn "Add $TRACEO_INSTALL_DIR to PATH manually."
      return 0
    fi
  fi

  echo "PATH updated in $rc_file. Run 'source $rc_file' or open a new terminal."
}

main() {
  need_cmd curl
  need_cmd tar
  command -v shasum >/dev/null 2>&1 || need_cmd sha256sum

  platform=$(detect_platform)
  archive_name="traceo_${platform}.tar.gz"
  base_url=$(release_base_url)

  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' EXIT INT HUP TERM

  archive_path="$tmp_dir/$archive_name"
  checksums_path="$tmp_dir/checksums.txt"

  mkdir -p "$TRACEO_INSTALL_DIR"

  curl -fsSL "$base_url/$archive_name" -o "$archive_path"
  curl -fsSL "$base_url/checksums.txt" -o "$checksums_path"

  checksum_ok "$archive_name" "$checksums_path"
  tar -xzf "$archive_path" -C "$tmp_dir"
  cp "$tmp_dir/traceo" "$TRACEO_INSTALL_DIR/traceo"
  chmod 0755 "$TRACEO_INSTALL_DIR/traceo"

  append_path_if_needed

  echo "traceo installed to $TRACEO_INSTALL_DIR/traceo"
}

main "$@"
