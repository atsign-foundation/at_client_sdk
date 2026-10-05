#!/usr/bin/env bash
#
# down.sh — stop the issuer and the invitations EE. What was issued, and the
# logs, stay in .ee/ until the next up.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

stop_issuer
if [[ -f "$STATE/docker-compose.yaml" ]]; then
  docker compose -f "$STATE/docker-compose.yaml" down -v >/dev/null 2>&1 || true
fi
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
ok "stopped the issuer and $CONTAINER"
