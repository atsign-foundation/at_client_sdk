#!/usr/bin/env bash
#
# up.sh — start a fresh Ephemeral Environment for the invitations example,
# and the issuer that hands its atSigns out to the app.
#
# Usage: up.sh
#
# ⚠️ This DESTROYS any previous EE and every key in it, and forgets what the
# issuer had issued. CRAM secrets are one-shot per atSign per environment, so
# a re-run is a teardown, not a restart. Atsigns an app activated against the
# old EE stay in that app's keychain but no longer exist.
#
# Environment: INV_EE_BASE (default 35000), INV_ISSUER_PORT (default 35100),
# INV_EE_IMAGE (default atsigncompany/ephemeral:latest, the EE built from the
# latest at_server production release; atsigncompany/ephemeral:dev_env is built
# from trunk, and build_ee.sh makes one from any at_server checkout).

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

say "Preflight"
command -v docker >/dev/null || die "docker is not on PATH"
command -v dart >/dev/null || die "dart is not on PATH"
grep -qE "^[^#]*[[:space:]]$ROOT_HOST([[:space:]]|$)" /etc/hosts \
  || die "/etc/hosts has no entry for $ROOT_HOST. Add: 127.0.0.1 $ROOT_HOST"
ok "/etc/hosts maps $ROOT_HOST"
# NOTE: a published image is pulled every time, because its tag moves: latest
# with each rebuild, dev_env with trunk. A local one, from build_ee.sh, only
# has to exist. Not
# `docker image inspect`, which under the containerd image store can refuse a
# short name that `docker image ls` finds.
if [[ "$IMAGE" == */* ]]; then
  docker pull -q "$IMAGE" >/dev/null || die "could not pull $IMAGE"
fi
[[ -n "$(docker image ls -q "$IMAGE")" ]] \
  || die "no image $IMAGE. Run build_ee.sh, or unset INV_EE_IMAGE."
ok "image $IMAGE"

say "Teardown"
stop_issuer
if [[ -f "$STATE/docker-compose.yaml" ]]; then
  docker compose -f "$STATE/docker-compose.yaml" down -v >/dev/null 2>&1 || true
fi
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
rm -rf "$STATE"
mkdir -p "$LOGS"
ok "removed $STATE"

# NOTE: no atSign list is mounted, so the EE creates its default 26,
# @alpha to @zulu.
say "Ephemeral Environment on $BASE"
cat > "$STATE/docker-compose.yaml" <<YAML
name: $CONTAINER
services:
  ephemeral:
    container_name: $CONTAINER
    image: $IMAGE
    ports:
      - '127.0.0.1:$BASE-$((BASE + 99)):$BASE-$((BASE + 99))'
    extra_hosts:
      - '$ROOT_HOST:127.0.0.1'
    environment:
      - EPHEMERAL_BASE_PORT=$BASE
      - DNS_FQDN=$ROOT_HOST
YAML
docker compose -f "$STATE/docker-compose.yaml" up -d >/dev/null
ok "container $CONTAINER started"

# NOTE: a fresh connection per probe, because the atDirectory drops a
# connection after its third not-found. perl's alarm stands in for timeout(1),
# which macOS lacks.
say "Waiting for the atDirectory"
ready=0
for _ in $(seq 1 90); do
  answer=$(printf 'alpha\n' \
    | perl -e 'alarm shift; exec @ARGV' 5 \
      openssl s_client -connect "$ROOT" -quiet 2>/dev/null \
    | head -1 | tr -d '\r@' || true)
  if [[ "$answer" == "$ROOT_HOST:"* ]]; then ready=1; break; fi
  sleep 2
done
(( ready == 1 )) || die "the atDirectory on $BASE never resolved alpha"
ok "atDirectory resolves alpha to $answer"

for _ in $(seq 1 30); do
  docker exec "$CONTAINER" cat /tmp/CRAM_Keys > "$STATE/cram_keys.txt" 2>/dev/null \
    && [[ -s "$STATE/cram_keys.txt" ]] && break
  sleep 1
done
[[ -s "$STATE/cram_keys.txt" ]] || die "could not read /tmp/CRAM_Keys from $CONTAINER"
ok "$(wc -l < "$STATE/cram_keys.txt" | tr -d ' ') CRAM secrets"

say "Issuer on http://localhost:$ISSUER_PORT"
(cd "$APP_DIR/issuer" && dart pub get >/dev/null)
nohup dart run "$APP_DIR/issuer/bin/issuer.dart" \
  --cram-keys "$STATE/cram_keys.txt" --state "$STATE/issued.json" \
  --root-domain "$ROOT" --port "$ISSUER_PORT" \
  --container "$CONTAINER" --network "${CONTAINER}_default" \
  > "$LOGS/issuer.log" 2>&1 &
echo $! > "$STATE/issuer.pid"
listening=0
for _ in $(seq 1 60); do
  curl -fsS "http://localhost:$ISSUER_PORT/atsigns" >/dev/null 2>&1 && { listening=1; break; }
  sleep 1
done
(( listening == 1 )) || { tail -20 "$LOGS/issuer.log" >&2; die "the issuer never started"; }
ok "issuer: $(curl -fsS "http://localhost:$ISSUER_PORT/atsigns")"

cat <<EOF

  Ready. Run the app twice, as two people:

    cd $APP_DIR
    flutter build macos --debug
    open -n build/macos/Build/Products/Debug/invitations.app
    open -n build/macos/Build/Products/Debug/invitations.app

  In each, "Get a new atSign" activates the next atSign the issuer has not
  issued. Stop everything with ee/down.sh.
EOF
