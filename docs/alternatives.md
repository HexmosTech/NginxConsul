# Alternatives to ngx_http_consul_backend_module

Research notes, October 2026. The goal is to pick a maintained path for
dynamic Consul backends in nginx.

## The module itself

`hashicorp/ngx_http_consul_backend_module` is a 2017 demo. The README says:
"This code is for example purposes only."

- The last functional change was in 2017.
- Commits after 2017 are license-header bots and compliance PRs.
- No issue or pull request mentions newer nginx compatibility.
- Twenty-three forks exist. Only one contains real changes.

The active fork is `JasonHonor/ngx_http_consul_backend_module`, last pushed in
June 2020. It is 15 commits ahead and includes:

- a C99 fix, equivalent to `patches/0001-consul-strlen-cast.patch`
- a newer nginx build
- aarch64 support
- a configurable Consul address
- a Dockerfile

It is five years old, has two stars, and its README still calls the code
"inspiration only." It also changes the directive syntax, so existing
configuration files would need edits. It is not a safe base.

## Native nginx `resolve`

Since nginx **1.27.3**, the open-source build supports:

- `resolver` and `resolver_timeout` inside an `upstream` block
- the `resolve` parameter on `server`
- `service=` for DNS SRV records

The upstream group must use a `zone`. Open-source nginx has passive failover,
not active health checks. Consul DNS returns only passing services by default,
so this is enough for most deployments.

See [../examples/native-resolve.conf](../examples/native-resolve.conf).

Advantages:

- no custom module
- no NDK
- no Go toolchain
- no patching
- addresses are cached, so nginx keeps serving during a Consul outage

This is the migration target.

## nginx-upsync-module

`weibocom/nginx-upsync-module` is a C module that syncs upstreams from Consul
or etcd into shared memory. It is actively maintained: commits in October 2026,
about 1.8k stars, and the README calls it production ready.

Trade-offs:

- still requires a custom nginx build
- syncs from Consul **KV**, not the service catalog, so something must write
  service addresses into KV
- more moving parts than native `resolve`

It is a reasonable choice if you already populate Consul KV.

## Consul Template

`hashicorp/consul-template` renders nginx configuration from Consul and reloads
nginx. Release v0.43.1 shipped on 21 October 2026, so it is maintained.

Trade-offs:

- no custom nginx build
- adds a daemon that writes files and triggers reloads
- reloads are heavier than in-place DNS updates

This is the official HashiCorp approach.

## Comparison

| Option | Maintained | Custom build | Extra daemon | Verdict |
|---|---|---|---|---|
| Native `resolve` | nginx core | No | No | Best long-term |
| nginx-upsync-module | Yes | Yes | No | Good if Consul KV is populated |
| Consul Template | Yes | No | Yes | Good if reloads are acceptable |
| JasonHonor fork | No (2020) | Yes | No | Do not adopt |
| This repo's module build | Patched locally | Yes | No | Bridge only |

## Decision

1. Ship nginx 1.30.6 with the two patches. This clears the CVEs with the
   smallest possible change.
2. Test native `resolve` on a non-critical host.
3. Remove the module, NDK, and Go from the build once native `resolve` is
   proven.
