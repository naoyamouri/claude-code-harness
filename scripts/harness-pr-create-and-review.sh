#!/usr/bin/env bash
# Create a PR, then synchronously produce its formal review receipt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
base=""
head=""
title=""
body=""
fill=0

usage() {
  echo "Usage: $0 --base REF --head REF (--fill | --title TITLE --body BODY)" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) base="${2:-}"; shift 2 ;;
    --head) head="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    --body) body="${2:-}"; shift 2 ;;
    --fill) fill=1; shift ;;
    *) usage; exit 2 ;;
  esac
done

[ -n "$base" ] && [ -n "$head" ] || { usage; exit 2; }
if [ "$fill" -eq 1 ]; then
  [ -z "$title$body" ] || { usage; exit 2; }
elif [ -z "$title" ] || [ -z "$body" ]; then
  usage
  exit 2
fi

command -v gh >/dev/null 2>&1 || { echo "gh CLI is required" >&2; exit 2; }
args=(pr create --base "$base" --head "$head")
if [ "$fill" -eq 1 ]; then args+=(--fill); else args+=(--title "$title" --body "$body"); fi
gh "${args[@]}"
if [ -x "${ROOT_DIR}/scripts/harness-pr-post-create-review.sh" ]; then
  bash "${ROOT_DIR}/scripts/harness-pr-post-create-review.sh"
else
  bash "${SCRIPT_DIR}/harness-pr-post-create-review.sh"
fi
