#!/bin/bash
# setup-codex.sh が実ユーザーの ~/.codex には書き込まず、一時的な出力先では進むことを確かめる。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SCRIPT_DIR/../scripts/setup-codex.sh"
REAL_HOME="$(python3 -c 'import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# clone は偽の git で必ず失敗させ、上流を取得せずに止める位置だけを見る
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/git"
chmod +x "$TMP/bin/git"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

run() {
  local dir="$1"
  shift
  (cd "$dir" && PATH="$TMP/bin:$PATH" "$@" 2>&1) || true
}

expect_blocked() {
  case "$2" in
    *"Disabled for"*) echo "PASS: $1" ;;
    *) fail "$1 was not blocked: $2" ;;
  esac
}

expect_allowed() {
  case "$2" in
    *"Disabled for"*) fail "$1 was blocked: $2" ;;
    *"Failed to clone"*) echo "PASS: $1" ;;
    *) fail "$1 did not reach clone: $2" ;;
  esac
}

ln -s "$REAL_HOME/.codex" "$TMP/link"

expect_blocked "user mode on the real ~/.codex" "$(run "$TMP" env CODEX_HOME="$REAL_HOME/.codex" bash "$SETUP" --user)"
expect_blocked "project mode with cwd at the real home" "$(run "$REAL_HOME" bash "$SETUP" --project)"
expect_blocked "symlink to the real ~/.codex" "$(run "$TMP" env CODEX_HOME="$TMP/link" bash "$SETUP" --user)"
expect_blocked "HOME overridden" "$(run "$TMP" env HOME="$TMP" CODEX_HOME="$REAL_HOME/.codex" bash "$SETUP" --user)"
expect_allowed "missing temporary CODEX_HOME" "$(run "$TMP" env CODEX_HOME="$TMP/new/.codex" bash "$SETUP" --user)"
expect_allowed "project mode in a temporary dir" "$(run "$TMP" bash "$SETUP" --project)"
