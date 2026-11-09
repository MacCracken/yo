# yo — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md). Audits → [`../audit/`](../audit/).
>
> **Last refresh**: 2026-11-08 (0.7.2: the first P(-1) audit). The snapshot, position, verification and kernel-coupling sections were re-checked against the code at this release; the dependency and family facts at 0.7.1, the same day.

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.7.2** |
| Cyrius pin | 6.7.18 · taar dep 0.6.2 |
| Status | **Both shipping backends work and are validated, and the tree is audited.** Linux is at POSIX-ping output parity for v4 + v6. AGNOS reaches ICMP through the sovereign kernel surface, is iron-validated, and passes its QEMU smoke. The 0.7.2 P(-1) fixed 25 findings ([report](../audit/2026-11-08-audit.md)). Windows / Apple are v1 backlog. |
| Backends | Linux (**working**) · AGNOS (**working, validated**) · Windows / Apple (post-1.0) |
| Tests | **483** assertions in `tests/yo.tcyr`; **37** guards mutation-checked (removing any one turns a suite red). `tests/yo.fcyr`: 20,000 deterministic fuzz rounds, 22 invariants, run plain and under `--poison`. `tests/integration/run.sh`: **28** end-to-end checks in a network namespace (0.7.1 fails 18). `tests/yo.bcyr`: 8 rows. Bare `cyrius test` also runs the `src/test.cyr` stub, so it reports 2 units. Exit codes are clamped to 1 (since 0.5.9). |
| Cleanliness | `cyrius audit` fully clean — fmt, lint, docs (every public fn documented) — and gated in CI. |
| Build size | **200,936 B** default (`.text` 195,946; 508 unreachable fns, 115,676 B). **86,248 B** with `CYRIUS_DCE=1`. AGNOS 215,144 B, or 84,072 B under DCE. iputils `ping` is 155,160 B, so the DCE build is smaller and the default build is not; the 1.0 size criterion turns on which one releases ship (roadmap 0.10.x). |
| Speed | 0.6.0, best of 3 × 100 `-c 1 -n 127.0.0.1`: **yo 381 µs** vs iputils 458 µs. 0.7.2 under a bash loop on this host: 448–449 µs against 444–445 µs for 0.7.1. Bench medians: `icmp_checksum` 64 B 96 ns, `icmp_build_echo_request` 206 ns, `ipv4_parse` 54 ns, `ipv6_parse` 309 ns, `output_ipv4_to_buf` 85 ns, `probe_reply_is_ours` raw+cksum 116 ns, PTR parse + hostname check 183 ns, question echo 107 ns. |
| Iron-validation host | archaemenid (Beelink SER, AMD) |
| Family position | First entry in the network-tools family; sibling to `dig` and `whirl`, all three on the `taar` substrate |

## Current position

**0.7.2 closed the first P(-1) audit.** 25 findings, all fixed; the decisions and
feature work it surfaced are on the roadmap. What remains before 1.0 is three bands
([`roadmap.md`](roadmap.md)):

- **0.8.x — backend parity.** AGNOS has kernel surface it does not use yet: `-W`
  through `sys_icmp_echo_ex` (`lib/syscalls_x86_64_agnos.cyr:2375`), ICMP counters
  through `sys_net_icmp_*` (`:2437-2443`), and Ctrl-C through `sys_sigprocmask` /
  `sys_signalfd` (`:1975`, `:1978`). All are vendored, and `src/` calls none of them.
  Linux needs aarch64-correct syscalls (see § Verification).
- **0.9.x — Linux completeness**: IPv6 nameservers, ICMP error replies, answer
  owner-name checks, signed release artifacts, the integer-flag wrap.
- **0.10.x — behaviour decisions, then the surface freeze.** The audit left a list
  of choices (loss-% format, continuous mode, `-W`/`-i` units, interval semantics,
  the unprivileged minimum interval, exit aggregation, `-v`, source filtering, the
  missing-resolv.conf default, DCE release builds) that have to be made before the
  CLI and output are frozen as the 1.0 contract.

## Verification — what is actually proven, and how

| Surface | Evidence | Gate |
|---|---|---|
| Linux ICMP v4 + v6, DNS both directions, scope IDs, v4-mapped, SOCK_RAW header strip, reply acceptance, CLI ranges, interruptible waits, no per-probe allocation | 483 unit assertions; 37 mutation-checked guards | `cyrius test` + `cyrius audit`, **in CI** |
| Every byte parser (DNS, resolv.conf, ICMP frames, cmsg, IPv6 literals) | 20,000 fuzz rounds, 22 invariants, plain and under `--poison` (a heap overrun exits 86) | `cyrius fuzz`, **in CI** |
| The SOCK_RAW fallback (v4 + v6), Ctrl-C, multi-target stop, RSS over a long run, the seq wrap, DNS end to end (PTR injection, a forged reply, fail-closed resolv.conf, CRLF) | `tests/integration/run.sh`: 28 checks in an `unshare` network + mount namespace with a fake DNS server | **in CI** under `sudo unshare` since 0.7.2 — that branch had not yet run on GitHub at release |
| AGNOS backend **compiles** | `cyrius build --agnos` | **in CI** |
| AGNOS backend **runs** | `scripts/agnos-qemu-smoke.sh`: boots agnos, types probes over QMP `send-key`, asserts on serial. 2/2 replies from the SLIRP gateway, `-s 3000` refused with EMSGSIZE, no kernel fault (2026-11-08). ⚠ the `ttl=64` it prints is a literal from `_ag_icmp_pong`, not a measurement | manual — needs the agnos / gnoboot / agnoshi checkouts, QEMU and OVMF |
| AGNOS on real hardware | agnos **1.51.7** burn, 2026-07-02: `yo google.com` **4/4 at 0% loss**, real DHCP lease. A gateway-literal run is not separately recorded (roadmap 0.8.x) | manual burn |
| aarch64 | ⚠ **builds clean and would be wrong.** `src/platform_linux.cyr`'s original paths use x86_64 syscall numbers (`_LX_SYS_*`); on aarch64, 44 is `fstatfs(2)`, not `sendto`. Code added at 0.7.2 uses the stdlib wrappers. yo ships x86_64 only, so this is latent | none (roadmap 0.8.x) |

## Dependencies (current)

**stdlib** (`cyrius.cyml [deps].stdlib`, 11 leaves — unchanged since the CLI landed):

```
string fmt alloc io vec str syscalls assert bench args flags
```

`args` + `flags` arrived with the CLI. DNS (0.4.0) and IPv6 (0.5.x) added none — the
resolver and the v6 framing are built directly on `platform_*` and stay in-tree.
`cyrius deps` vendors these into the gitignored `lib/`, hash-locked in `cyrius.lock`
(29 files at the 6.7.18 pin, each byte-identical to the bundled stdlib; `poison` and
`alloc_cx` arrive transitively).

**Pin status**: `cyrius = "6.7.18"`, the newest cyrius release as of 2026-11-08. The 11
declared modules have lost no symbol and changed no arity since 6.6.2 (`docs/api-surface.snapshot`:
233 at 6.6.2, 254 at 6.6.20 and 6.7.9, 258 at 6.7.18). Read cyrius's
`docs/development/ecosystem-migration.md` at the target tag before the next move.

**taar** (`cyrius.cyml [deps.taar]`) — **0.6.2**, `modules = ["dist/taar.cyr"]`, commit
pin `d203629` in `cyrius.lock`. yo consumes **one symbol**, `ipv4_parse`; the bundle's
`socket`/`dns` modules ride along and DCE out. No fn or var name in the bundle is also
defined in yo's `src/` (checked at 0.7.1), so cyrius's "last definition wins" cannot
swap a body.

**`path = "../taar"` is a local-mode override** (cyrius ≥ 6.7.6). A default `cyrius deps` /
`build` / `test` builds the tag, checks the commit pin, and prints
`hint: 1 dep has a local checkout not in use (taar)`. `CYRIUS_LOCAL=1` (or `--local`)
builds `../taar` from `build/local-deps/lib/` and writes neither `lib/` nor
`cyrius.lock`. CI and `release.yml` resolve with `cyrius deps --locked`, which fails by
name on a committed lock the tags no longer produce. `--locked` does not flag a leftover
old-tag commit row; regenerate the lock at a tag bump.

## Family (all three consumers now real)

| Repo | Version | Cyrius pin | taar | Relationship |
|---|---|---|---|---|
| **taar** | 0.6.2 | 6.7.18 | — | Substrate. yo folded `src/ipv4.cyr` onto it at 0.5.5. |
| **dig** | 0.4.1 | 6.6.2 | 0.5.0 | DNS resolver. Second `ipv4` consumer — it forced the extraction. |
| **whirl** | 0.6.14 | 6.6.2 | 0.5.0 | curl/wget. Third consumer; uses taar's `socket` + `dns`, which yo does not. |

**Family drift**: yo is the first consumer on 6.7.18 and taar 0.6.2. `dig` and `whirl`
pin 6.6.2 and taar 0.5.0. The evidence gathered here applies to them when they follow:
no stdlib removals or arity changes across 6.6.2 → 6.7.18 for these 11 modules, taar's
`ipv4_*` surface unchanged, and the 6.7.x checks in yo's 0.7.0 and 0.7.1 CHANGELOG
entries. Each still needs that checklist run against its own source. yo's 0.7.2 resolver
findings (I, K, N) are worth checking in `dig`, which carries its own resolver.

## Kernel coupling (AGNOS backend only)

The AGNOS backend reaches ICMP through the sovereign kernel ABI; the Linux backend has
no AGNOS coupling at all. The kernel logic lives in `agnos/kernel/core/net_icmp.cyr`
(`icmp_ping` + `net_handle_icmp`) and has been reachable from ring 3 since **agnos 1.45.4**.

**The kernel chose the focused shape, and yo adapted to it** — `icmp_echo(dst_ip)`#55 is
one-shot: it sends, waits, and returns the RTT in one blocking call. So
`platform_agnos.cyr` collapses `_send_to + _recv` onto it and synthesises the reply
packet locally. The rationale and its costs are in
[ADR 0002](../adr/0002-focused-kernel-icmp-syscall.md); the acceptance consequences in
[architecture note 001](../architecture/001-reply-acceptance-invariants.md).

`src/probe.cyr` and `src/dns.cyr` call this platform surface. Both backends implement
all of it; the right-hand column is what AGNOS does:

| Platform call | AGNOS implementation |
|---|---|
| `platform_icmp_open()` | returns a sentinel fd (900) — there is no socket |
| `platform_icmp_send_to(fd, addr, pkt, len)` | **stores** the request (at most 2048 B; a longer one is refused with -EMSGSIZE); nothing is sent yet |
| `platform_icmp_recv_ext(fd, buf, max, ttl_out)` | calls `sys_icmp_echo`#55, then synthesises the reply from the stored request. `ttl_out` gets a **nominal 64** — #55 does not surface the real TTL |
| `platform_wait_readable` / `platform_sleep_interruptible` | "readable" at once (the wait happens inside #55) / a plain `sys_sleep_ms`#41; neither reports an interrupt |
| `platform_icmp6_*` | **unavailable** (`-1`) — agnos has no ICMPv6 syscall, so yo's v6 path is inert there |
| `platform_resolve_ifindex(name)` | **0** — no ifindex concept exposed to ring 3 |
| `platform_udp_open / _send_to / _recv` | `sys_udp_bind` / `sys_udp_send` / `sys_udp_recv` (#51-53), listener-id based, non-blocking with a host-side deadline. The kernel delivers by destination port alone, so `_recv` drops datagrams whose source is not the recorded peer (`platform_peer_match`) |
| `platform_random_u16()` | `sys_getrandom`#45, degrading to the clock if it fails |
| `platform_read_file(path, buf, max)` | `sys_open` / `sys_read` / `sys_close` |
| `platform_set_recv_timeout_ms(fd, ms)` | stores the value for the **UDP** poll loop only. ⚠ It cannot affect ICMP: #55's ~3 s bound is fixed inside the kernel, so **`-W` is silently inapplicable on AGNOS** until yo adopts `icmp_echo_ex`#100 (roadmap 0.8.x) |
| `platform_now_us()` / `platform_sleep_ms(ms)` | `sys_uptime_ms`#40 × 1000 / `sys_sleep_ms`#41 |
| `platform_install_interrupt_watch()` | a `-1` stub. The kernel has `sigprocmask`#17 / `signalfd`#18 and the stdlib wraps them; wiring them is roadmap 0.8.x |
| `platform_dns_server()` | `sys_net_dns_server` (`net_config`#61 field 3) — the DHCP-leased resolver, preferred over `/etc/resolv.conf` |

On Linux the same surface is POSIX:
- **TTL / hop limit:** `IP_RECVTTL` and `recvmsg` cmsg walking for the real TTL;
  `IPV6_RECVHOPLIMIT` for v6.
- **Waits:** `ppoll` on the socket and the SIGINT signalfd against the `-W` deadline.
  `SO_RCVTIMEO` remains as a backstop, and it is what DNS waits on.
- **DNS:** a UDP socket connected to the nameserver.
- **Scope IDs:** a validated `/sys/class/net/<name>/ifindex` lookup, or a numeric zone.

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| **IPv6 on agnos** — blocks `yo -6` there | agnos has **no IPv6 stack at all** (no `0x86DD` arm, no NDP, no ICMPv6); formally backlogged in agnos's `roadmap.md` § OPEN | agnos |
| Integer flags wrap silently past 2^64 | `lib/flags.cyr` has no overflow check (or cmdit, if it has one — roadmap 0.9.x) | cyrius / cmdit |
| Family toolchain drift | `dig` and `whirl` (both 6.6.2 / taar 0.5.0) trail yo's 6.7.18 / taar 0.6.2 | dig + whirl |

## Consumers

None yet. yo IS a leaf consumer of the kernel; nothing depends on yo today.

## Cross-references

- [`roadmap.md`](roadmap.md) — the plan through v1.0 and the v1 backlog
- [`../audit/2026-11-08-audit.md`](../audit/2026-11-08-audit.md) — the 0.7.2 P(-1): findings, method, deferred items
- [`../adr/0001-per-backend-sovereignty.md`](../adr/0001-per-backend-sovereignty.md) · [`../adr/0002-focused-kernel-icmp-syscall.md`](../adr/0002-focused-kernel-icmp-syscall.md)
- [`../architecture/001-reply-acceptance-invariants.md`](../architecture/001-reply-acceptance-invariants.md) — what yo checks before believing a reply
- [`../guides/diagnosing-no-reply.md`](../guides/diagnosing-no-reply.md) — the `--diag` decision tree
- `agnos/kernel/core/net_icmp.cyr` (`icmp_ping`) + `agnos/kernel/core/syscall.cyr` (`num == 55`) — the kernel ICMP logic and the ring-3 syscall that exposes it. Read the #55 comment block for the contract: RTT in ms, fixed ~3 s bound, 100 Hz resolution.
- [agnosticos shared-crates.md § yo + taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — substrate plan

> **Doc hygiene note (2026-08-26, 0.6.0):** this file had drifted twice over, in two
> different ways, and both are worth remembering.
>
> **It lagged reality.** It described the AGNOS backend as gated and never-run while
> that backend had shipped at 0.5.3, been iron-validated at agnos 1.51.7 in July, and
> been running in QEMU since 0.5.11. The `args.cyr` gate it listed as open had closed
> at cyrius 6.0.87. Every one of those facts was checkable in source; none was checked.
> **Verify against code — including the claims in this file — never against prose,
> including this repo's own.**
>
> **And it had become a log.** ~80 lines of per-release "carryover" narrative for
> 0.3.0 through 0.5.2 sat under a heading that says NOT A LOG, duplicating
> `CHANGELOG.md`. That history now lives only in the CHANGELOG, where it belongs; this
> file is one current-state block again.
