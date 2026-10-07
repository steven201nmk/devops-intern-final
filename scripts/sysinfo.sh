#!/usr/bin/env bash
#
# sysinfo.sh - report the host environment.
#
# Usage:   ./scripts/sysinfo.sh
# Output:  current user and effective UID, hostname, kernel release,
#          system date (ISO-8601, UTC), disk usage, memory usage and
#          Docker daemon status.
# Exit:    0 when the report was printed.
#
set -euo pipefail

section() {
  printf '\n== %s ==\n' "$1"
}

section "User"
printf 'User:            %s\n' "$(id -un)"
printf 'Effective UID:   %s\n' "$(id -u)"

section "Host"
printf 'Hostname:        %s\n' "$(hostname 2>/dev/null || uname -n)"
printf 'Kernel release:  %s\n' "$(uname -r)"

section "Date (ISO-8601, UTC)"
date -u +"%Y-%m-%dT%H:%M:%SZ"

section "Disk usage (/)"
df -h /

section "Memory usage"
if command -v free >/dev/null 2>&1; then
  free -h
elif [ -r /proc/meminfo ]; then
  grep -E '^(MemTotal|MemAvailable|SwapTotal):' /proc/meminfo
else
  echo "Memory information is not available on this system."
fi

section "Docker daemon"
if ! command -v docker >/dev/null 2>&1; then
  echo "Status: docker CLI not installed"
elif docker info >/dev/null 2>&1; then
  printf 'Status: running (server version %s)\n' \
    "$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)"
else
  echo "Status: docker CLI installed, but the daemon is not reachable (stopped, or this user lacks permission)"
fi
