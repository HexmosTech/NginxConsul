#!/usr/bin/env bash
# Build nginx with the Consul backend module.
#
# This script never writes to /etc/nginx and never runs "make install".
# It stages a binary and the Go shared object under build/stage, then packs
# them into dist/. Installation is a separate, reviewable step.
#
# Usage: ./build.sh [--ci] [--clean]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$ROOT/versions.env"

CI=0
CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --ci) CI=1 ;;
    --clean) CLEAN=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

WORK="$ROOT/build"
STAGE="$WORK/stage"
DIST="$ROOT/dist"
SRC="$WORK/src"
DL="$WORK/downloads"
MODULE="$WORK/module"

if [[ "$CLEAN" == "1" ]]; then
  rm -rf "$WORK" "$DIST"
fi
mkdir -p "$DL" "$SRC" "$STAGE" "$DIST"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}
for c in curl tar sha256sum patch make gcc go; do need "$c"; done

fetch() { # url dest sha256
  local url="$1" dest="$2" sha="$3"
  if [[ -f "$dest" ]] && echo "$sha  $dest" | sha256sum -c --status; then
    return 0
  fi
  echo "==> download $url"
  curl -fL --retry 3 -o "$dest" "$url"
  echo "$sha  $dest" | sha256sum -c -
}

fetch "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
      "$DL/nginx-${NGINX_VERSION}.tar.gz" "$NGINX_SHA256"
fetch "https://github.com/simpl/ngx_devel_kit/archive/v${NDK_VERSION}.tar.gz" \
      "$DL/ngx_devel_kit-${NDK_VERSION}.tar.gz" "$NDK_SHA256"

echo "==> extract"
rm -rf "$SRC/nginx-${NGINX_VERSION}" "$SRC/ngx_devel_kit-${NDK_VERSION}"
tar -C "$SRC" -xzf "$DL/nginx-${NGINX_VERSION}.tar.gz"
tar -C "$SRC" -xzf "$DL/ngx_devel_kit-${NDK_VERSION}.tar.gz"

echo "==> stage module source"
rm -rf "$MODULE"
cp -a "$ROOT/third_party/ngx_http_consul_backend_module" "$MODULE"
for p in "$ROOT"/patches/*.patch; do
  echo "==> apply $(basename "$p")"
  patch -d "$MODULE" -p1 --forward < "$p"
done

echo "==> build Go shared library"
mkdir -p "$STAGE/usr/local/nginx/ext"
(
  cd "$MODULE"
  if [[ ! -f go.mod ]]; then
    go mod init github.com/hashicorp/ngx_http_consul_backend_module
    go mod tidy
  fi
  CGO_CFLAGS="-I $SRC/ngx_devel_kit-${NDK_VERSION}/src" \
    go build -buildmode=c-shared \
      -o "$STAGE/usr/local/nginx/ext/ngx_http_consul_backend_module.so" \
      ./src/ngx_http_consul_backend_module.go
)
chmod 0755 "$STAGE/usr/local/nginx/ext/ngx_http_consul_backend_module.so"

echo "==> configure nginx"
(
  cd "$SRC/nginx-${NGINX_VERSION}"
  # -g -O0 matches the build that already runs on the hosts. Change it in a
  # separate commit, after a benchmark, not during a security update.
  CFLAGS="-g -O0" ./configure \
    --with-debug \
    --without-pcre2 \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_auth_request_module \
    --with-http_v2_module \
    --with-http_dav_module \
    --with-http_slice_module \
    --with-http_addition_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-mail_ssl_module \
    --with-stream_ssl_module \
    --add-module="$SRC/ngx_devel_kit-${NDK_VERSION}" \
    --add-module="$MODULE"
  echo "==> compile"
  make -j"$(nproc)"
)

install -D -m 0755 "$SRC/nginx-${NGINX_VERSION}/objs/nginx" "$STAGE/usr/sbin/nginx"

echo "==> verify"
"$STAGE/usr/sbin/nginx" -V 2>&1 | tee "$STAGE/BUILD_INFO"
grep -q "nginx/${NGINX_VERSION}" "$STAGE/BUILD_INFO" || {
  echo "version mismatch: expected nginx/${NGINX_VERSION}" >&2
  exit 1
}

cat >> "$STAGE/BUILD_INFO" <<EOF
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
consul_module_commit=${CONSUL_MODULE_COMMIT}
build_os=$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release)
EOF

HOST_OS="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')"
ARCHIVE="$DIST/nginx-${NGINX_VERSION}-consul-${HOST_OS}.tar.gz"
tar -C "$STAGE" -czf "$ARCHIVE" .
(
  cd "$DIST"
  sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)

echo
echo "artifact: $ARCHIVE"
cat "$ARCHIVE.sha256"
echo
echo "Install with Ansible. Do not run make install on a live host."
