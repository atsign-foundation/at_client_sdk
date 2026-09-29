# lib.sh — settings and helpers shared by the invitations EE scripts.
#
# Sourced, never executed.

APP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE="$APP_DIR/.ee"
LOGS="$STATE/logs"

BASE="${INV_EE_BASE:-35000}"
ISSUER_PORT="${INV_ISSUER_PORT:-35100}"
IMAGE="${INV_EE_IMAGE:-atsigncompany/ephemeral:dev_env}"
CONTAINER="invitations-ee"
ROOT_HOST="vip.ve.atsign.zone"
ROOT="$ROOT_HOST:$BASE"

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32mok\033[0m   %s\n' "$*"; }
die()  { printf '\n\033[1;31m%s: %s\033[0m\n' "$(basename "$0")" "$*" >&2; exit 1; }

stop_issuer() {
  if [[ -f "$STATE/issuer.pid" ]]; then
    kill "$(cat "$STATE/issuer.pid")" 2>/dev/null || true
    rm -f "$STATE/issuer.pid"
  fi
}
