# yo

**Yodel-Out** — ICMP echo probe written in [Cyrius](https://github.com/MacCracken/cyrius). Sovereign reimplementation of `ping`.

> *"Like a yodel across an Alpine valley, `yo` sends a small call into the network and waits for the return. The time between the call and the answer is the measure of the path between you and the host."*

## What it does

```sh
$ yo 192.168.1.1
yo 192.168.1.1 — 64 bytes
  seq=0  rtt=0.42 ms
  seq=1  rtt=0.39 ms
  seq=2  rtt=0.41 ms
^C
3 sent · 3 received · 0% loss · min/avg/max = 0.39/0.41/0.42 ms
```

Same shape as `ping`, Cyrius-native end to end:

- Per-backend sovereignty: the **Linux backend** uses POSIX `socket()` pragmatically (unprivileged SOCK_DGRAM ICMP with SOCK_RAW fallback). The **AGNOS backend** (future) will use the sovereign `icmp_echo` / `net_send_raw` kernel primitives per the [AGNOS kernel-growth posture](https://github.com/MacCracken/agnosticos/blob/main/docs/development/state.md).
- No `libc`, no `glibc`, no `musl`. Statically linked against the Cyrius stdlib only.
- Reads naturally as a verb: `yo google.com`, `yo -c 4 192.168.1.1`, `yo -W 2 router.local`.

## Platforms

| Backend | Status | Notes |
|---|---|---|
| **Linux** | working (pre-1.0) | `src/platform_linux.cyr` — unprivileged SOCK_DGRAM ICMP, falls back to SOCK_RAW. Needs the caller's GID to fall inside `/proc/sys/net/ipv4/ping_group_range` for the unprivileged path. |
| **AGNOS** | planned | will use the sovereign `icmp_echo` / `net_send_raw` syscalls when agnos lands the ICMP surface |
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
sh scripts/install.sh                  # copies build/yo → ~/.cyrius/bin/
```

Or drop the built binary anywhere on `$PATH`. No runtime deps.

## Family

`yo` is the first entry in the **AGNOS network-tools family** (English-wordplay / trickster lane):

| Tool | Sovereign equivalent of | Role |
|---|---|---|
| **yo** | `ping` | ICMP echo probe — *"is this host reachable, and how far away?"* |
| **whirl** | `curl` + `wget` | HTTP / HTTPS transfer — *"the packet whirls out, the response whirls back"* |
| **dig** | `dig` | DNS resolver — *"dig out the address record"* |

All three consume **taar** (Hindi तार, *wire/string/connection*) — the network-probe substrate library that owns ICMP / sockets / DNS / TCP / TLS / HTTP-client primitives. `taar` extracts from `yo` when the second consumer arrives (cf. the `mihi → iam/chakshu` extraction pattern).

## Status

Pre-1.0. See [`docs/development/state.md`](docs/development/state.md) for current version + surface + iron-validation status, and [`docs/development/roadmap.md`](docs/development/roadmap.md) for the milestone path through v1.0.

## License

GPL-3.0-only — see [LICENSE](LICENSE).

## Genesis

Part of [AGNOS](https://github.com/MacCracken/agnosticos) — the AI-native general operating system. AGNOS first-party tools follow [first-party-standards.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md) and [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-documentation.md).
