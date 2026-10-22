#!/usr/bin/env bash
# Smoke test for the staged binary. Does not touch the system nginx.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$ROOT/versions.env"

BIN="${1:-$ROOT/build/stage/usr/sbin/nginx}"
SO="${2:-$ROOT/build/stage/usr/local/nginx/ext/ngx_http_consul_backend_module.so}"

[[ -x "$BIN" ]] || { echo "binary not found: $BIN" >&2; exit 1; }
[[ -f "$SO" ]] || { echo "module not found: $SO" >&2; exit 1; }

"$BIN" -V 2>&1 | grep -q "nginx/${NGINX_VERSION}" || {
  echo "wrong nginx version" >&2
  "$BIN" -V
  exit 1
}

# ELF magic. Avoids a dependency on the file(1) package.
MAGIC="$(od -An -tx1 -N4 "$SO" | tr -d ' \n')"
[[ "$MAGIC" == "7f454c46" ]] || { echo "not an ELF file: $SO" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/conf" "$TMP/logs"

cat > "$TMP/conf/nginx.conf" <<EOF
pid $TMP/nginx.pid;
error_log stderr;
events {}
http {
    access_log off;
    server {
        listen 127.0.0.1:18080;
        location / { return 200 "ok\n"; }
    }
}
EOF

"$BIN" -p "$TMP" -c conf/nginx.conf -t
echo "smoke: ok (nginx ${NGINX_VERSION})"
