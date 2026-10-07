#!/usr/bin/env bash
#
# healthcheck.sh - assert that a URL answers with HTTP 200.
#
# Usage:   ./scripts/healthcheck.sh [URL]
#          URL defaults to http://localhost:8080
# Exit:    0  the URL returned HTTP 200
#          1  the URL answered, but with a status other than 200
#          2  the URL could not be reached (connection refused, DNS, timeout)
#          3  curl is not installed
#
set -euo pipefail

readonly DEFAULT_URL="http://localhost:8080"
readonly TIMEOUT_SECONDS=5

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  # print the comment header above as usage text
  awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "$0"
  exit 0
fi

url="${1:-$DEFAULT_URL}"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required but was not found in PATH" >&2
  exit 3
fi

echo "Checking ${url} ..."

# -s: no progress bar, -o /dev/null: discard the body,
# -w: print only the status code. Without -f, curl exits 0 for any HTTP
# status, so a non-zero exit here means the server could not be reached.
if ! status="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT_SECONDS" "$url")"; then
  echo "FAIL: ${url} is unreachable (no HTTP response within ${TIMEOUT_SECONDS}s)" >&2
  exit 2
fi

if [ "$status" = "200" ]; then
  echo "OK: ${url} returned HTTP 200"
  exit 0
fi

echo "FAIL: ${url} returned HTTP ${status}, expected 200" >&2
exit 1
