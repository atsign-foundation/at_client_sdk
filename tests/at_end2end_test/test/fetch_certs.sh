#!/usr/bin/env bash
set -euo pipefail

# Copies the atDirectory's and the atServers' certificate directories out of an
# image whose certificates are kept renewed, into ve-certs/ beside this script,
# for certs-overlay.yaml to mount over a release-pinned image's. A pinned image
# keeps the certificates it was built with, and they expire.
#
#   ./fetch_certs.sh [IMAGE]    # IMAGE defaults to atsigncompany/virtualenv:dev_env

cd "$(dirname "$0")"
image="${1:-atsigncompany/virtualenv:dev_env}"

docker pull -q "$image" >/dev/null
cid=$(docker create "$image")
trap 'docker rm "$cid" >/dev/null' EXIT

mkdir -p ve-certs/root ve-certs/secondary
docker cp "$cid:/atsign/root/certs/." ve-certs/root/
docker cp "$cid:/atsign/secondary/base/certs/." ve-certs/secondary/

for cert in ve-certs/root/fullchain.pem ve-certs/secondary/fullchain.pem \
    ve-certs/secondary/mtls/fullchain.pem; do
  if ! openssl x509 -checkend 0 -noout -in "$cert" >/dev/null; then
    echo "*** ${cert} from ${image} has expired as well" >&2
    exit 1
  fi
done
echo "*** Certificates from ${image}," \
  "$(openssl x509 -noout -enddate -in ve-certs/root/fullchain.pem)"
