# NginxConsul

Custom nginx build with the HashiCorp Consul backend module, refreshed to
nginx 1.30.6. Based on the original Ansible build by lovestaco.

The build produces two files:

- `usr/sbin/nginx`
- `usr/local/nginx/ext/ngx_http_consul_backend_module.so`

It never touches `/etc/nginx` and never runs `make install`.

## What this is

This is the custom nginx build for environments that need the `consul`
directive. Stock nginx does not have it, so the build adds the HashiCorp
module and its Go shared library.

The build is the same design as the original Ansible role, with four changes:

- nginx is updated from 1.24.0/1.30.4 to **1.30.6**
- the module source is pinned and vendored
- the two patches are explicit files, not inline edits
- the build stages files instead of running `make install`

## How it helps

- **No vhost changes.** `consul $backend service-name;` keeps working.
- **Newer nginx.** The binary moves to the current stable release.
- **Safe deploy.** `/etc/nginx` stays in place. Only the binary and the
  module are replaced.
- **Rollback.** If `nginx -t` fails, the previous binary and module are
  restored.
- **One artifact.** Both hosts get the same versioned tarball and checksum.

## Version note

nginx 1.30.6 is the current stable release. It also includes the October 2026
security fixes:

- `CVE-2026-15176`
- `CVE-2026-93479`
- `CVE-2026-97629`

Version 1.30.6 also contains fixes for `CVE-2026-95101` and `CVE-2026-97205`.
Those do not apply to this build because HTTP/3 is not enabled.

The module is a 2017 HashiCorp demo. The long-term target is native nginx
`resolve`, which removes the module, NDK, and Go from the build. See
[docs/alternatives.md](docs/alternatives.md).

## Design rules

1. `/etc/nginx` stays in place. This repo never moves, deletes, or overwrites it.
2. `make install` is never run on a live host.
3. Every input is pinned and checksummed.
4. Installation swaps the binary, runs `nginx -t`, and restores the backup on failure.
5. The Ansible role owns installation. This repo owns the artifact.

## Layout

```
.
├── build.sh                  # build, stage, pack. No install.
├── versions.env              # pinned versions and checksums
├── Dockerfile                # reproducible build image
├── patches/
│   ├── 0001-consul-strlen-cast.patch
│   └── 0002-consul-dlopen-path.patch
├── third_party/
│   └── ngx_http_consul_backend_module/   # vendored, no .git
├── examples/
│   └── native-resolve.conf   # replacement without the module
├── test/
│   └── smoke.sh
└── docs/
    └── alternatives.md
```

## Build

Host prerequisites: `build-essential`, `libpcre3-dev`, `zlib1g-dev`,
`libssl-dev`, `curl`, `patch`, and Go 1.26 or newer.

```bash
./build.sh
```

Docker:

```bash
make docker
```

Artifacts land in `dist/`:

```
dist/nginx-1.30.6-consul-ubuntu22.04.tar.gz
dist/nginx-1.30.6-consul-ubuntu22.04.tar.gz.sha256
```

Build on the **oldest** target release. A binary built against a newer glibc
can fail on an older host.

## Release

A tag that matches `v*` builds the artifact on Ubuntu 22.04 and publishes a
GitHub Release. The release contains:

- `nginx-<version>-consul-ubuntu22.04.tar.gz`
- `nginx-<version>-consul-ubuntu22.04.tar.gz.sha256`

The tag must match `NGINX_VERSION` in `versions.env`. For nginx 1.30.6, the
tag is `v1.30.6`. The workflow rejects a mismatched tag.

The release asset is permanent and versioned by the tag. It is not the
temporary workflow artifact.

Download URL:

```text
https://github.com/OWNER/NginxConsul/releases/download/v<version>/nginx-<version>-consul-ubuntu22.04.tar.gz
```

Ansible example:

```yaml
- name: Download the nginx artifact and checksum
  get_url:
    url: "https://github.com/OWNER/NginxConsul/releases/download/v{{ nginx_version }}/{{ item }}"
    dest: "/tmp/{{ item }}"
    mode: "0644"
  loop:
    - "nginx-{{ nginx_version }}-consul-ubuntu22.04.tar.gz"
    - "nginx-{{ nginx_version }}-consul-ubuntu22.04.tar.gz.sha256"

- name: Verify the artifact
  command: "sha256sum -c nginx-{{ nginx_version }}-consul-ubuntu22.04.tar.gz.sha256"
  args:
    chdir: /tmp
```

Replace `OWNER` with the repository owner. Do not use the `latest` URL because
the asset name contains the version.

## Install

Installation is handled by your deployment tooling. The order is:

1. Stop nginx.
2. Back up `/usr/sbin/nginx` and the existing `.so`.
3. Unpack the new files to a temporary path.
4. Move the new `.so` into `/usr/local/nginx/ext/`.
5. Move the new binary to `/usr/sbin/nginx`.
6. Run `/usr/sbin/nginx -t`.
7. Start nginx.
8. On any failure, restore both backups and start the old binary.

Do not copy the stock `/etc/nginx` from the tarball. The tarball does not
contain one.

## Verify

```bash
/usr/sbin/nginx -v          # nginx version: nginx/1.30.6
/usr/sbin/nginx -V 2>&1 | grep -o 'with-http_[a-z0-9_]*' | sort
curl -skI https://example.com/ | head -1
```

The binary is patched to load the module from
`/usr/local/nginx/ext/ngx_http_consul_backend_module.so`.

## Background

The original role and its write-up come from June 2025, when the target was
nginx 1.24.0:

- <https://dev.to/lovestaco/building-nginx-with-the-consul-backend-module-via-ansible-3pci>

That article omits the destructive purge task and one of the two patches.
Treat it as background, not as a procedure.

## Licensing

The build scripts in this repo are MIT. The vendored module is MPL-2.0.
nginx is BSD-2-Clause. See [NOTICE](NOTICE).
