# yo

**Yodel-Out** — ICMP echo probe written in [Cyrius](https://github.com/MacCracken/cyrius). Sovereign reimplementation of `ping`.

> *"Like a yodel across an Alpine valley, `yo` sends a small call into the network and waits for the return. The time between the call and the answer is the measure of the path between you and the host."*

## What it does

```sh
$ yo -c 3 1.1.1.1
yo 1.1.1.1 — 56 bytes
  seq=0  ttl=56  rtt=6.09 ms
  seq=1  ttl=56  rtt=6.00 ms
  seq=2  ttl=56  rtt=8.67 ms
3 sent · 3 received · 0% loss · min/avg/max = 6.00/6.92/8.67 ms

$ yo 8.8.8.8            # reverse DNS in the banner, unless -n
yo 8.8.8.8 (dns.google) — 56 bytes
  seq=0  ttl=116  rtt=9.12 ms
```

Same shape as `ping`, Cyrius-native end to end:

- Per-backend sovereignty: the **Linux backend** uses POSIX `socket()` pragmatically (unprivileged SOCK_DGRAM ICMP with SOCK_RAW fallback), reached by raw syscall number — no libc. The **AGNOS backend** ships and uses sovereign ring-3 syscalls only, with no `socket()` anywhere on that path. See [ADR 0001](docs/adr/0001-per-backend-sovereignty.md).
- No `libc`, no `glibc`, no `musl`. Statically linked against the Cyrius stdlib only.
- Reads naturally as a verb: `yo google.com`, `yo -c 4 192.168.1.1`, `yo -W 2 router.local`.

## Platforms

| Backend | Status | Notes |
|---|---|---|
| **Linux** | working (pre-1.0) | `src/platform_linux.cyr` — unprivileged SOCK_DGRAM ICMP, falls back to SOCK_RAW. Needs the caller's GID to fall inside `/proc/sys/net/ipv4/ping_group_range` for the unprivileged path. |
| **AGNOS** | working (pre-1.0) | `src/platform_agnos.cyr` — sovereign `icmp_echo`(#55) + `udp_*`(#51-54) + `net_config`(#61). Validated on iron (agnos 1.51.7 burn: `yo google.com` 4/4 at 0% loss) and in QEMU (`scripts/agnos-qemu-smoke.sh`). Not at feature parity: no ICMPv6, no `%zone` scope IDs, no Ctrl-C, and `-W` is fixed at the kernel's ~3 s bound — see [ADR 0002](docs/adr/0002-focused-kernel-icmp-syscall.md). |
| **Windows** | post-1.0 | |
| **Apple** | post-1.0 | |

## Why use it

- **Cyrius-native** — same toolchain that builds the AGNOS kernel, same sovereignty story end to end.
- **Tiny** — single static binary, no shared-lib drift.
- **Predictable timing** — no `libc` jitter; the only thing between `clock_gettime` and the wire is the kernel.
- **Wordplay readability** — `yo router` is what your brain wants to type when you're checking if the router is up.

## Build

```sh
cyrius deps                            # resolve stdlib + sibling deps
cyrius build src/main.cyr build/yo     # compile
cyrius test                            # run [build].test + tests/*.tcyr
```

Toolchain pin lives in `cyrius.cyml` (`[package].cyrius`). Don't hardcode it in CI YAML.

## Install

```sh
cp build/yo ~/.cyrius/bin/             # or anywhere on $PATH
```

Single static binary, no runtime deps. For the unprivileged path your gid must fall
inside `/proc/sys/net/ipv4/ping_group_range`; otherwise yo falls back to `SOCK_RAW`,
which needs `CAP_NET_RAW`. If a probe comes back silent, `yo --diag <host>` says which
of those you hit — see [the diagnostic guide](docs/guides/diagnosing-no-reply.md).

## Family

`yo` is the first entry in the **AGNOS network-tools family** (English-wordplay / trickster lane):

| Tool | Sovereign equivalent of | Role |
|---|---|---|
| **yo** | `ping` | ICMP echo probe — *"is this host reachable, and how far away?"* |
| **whirl** | `curl` + `wget` | HTTP / HTTPS transfer — *"the packet whirls out, the response whirls back"* |
| **dig** | `dig` | DNS resolver — *"dig out the address record"* |

All three consume **taar** (Hindi तार, *wire/string/connection*) — the network-probe substrate library. The extraction happened at yo 0.5.5, on the second-consumer trigger: `dig` grew a real resolver and the two shipped a byte-identical IPv4 parser, so the codec moved out. yo consumes exactly one taar symbol, `ipv4_parse`; taar's `socket`/`dns` modules ride along in the bundle and are eliminated from yo's binary.

## Status

Pre-1.0. See [`docs/development/state.md`](docs/development/state.md) for current version + surface + iron-validation status, and [`docs/development/roadmap.md`](docs/development/roadmap.md) for the milestone path through v1.0.

## License

GPL-3.0-only — see [LICENSE](LICENSE).

## Genesis

Part of [AGNOS](https://github.com/MacCracken/agnosticos) — the AI-native general operating system. AGNOS first-party tools follow [first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md) and [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-documentation.md).
