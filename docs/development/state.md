# yo — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-08-26 (0.6.0 — documentation reconciliation + the v1.0-criteria pass).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.6.0** |
| Cyrius pin | 6.5.35 · taar dep 0.5.0 |
| Status | **Both shipping backends work and are validated.** Linux is at full POSIX-ping output parity for v4 + v6. AGNOS reaches ICMP through the sovereign kernel surface, is iron-validated, and has an automated QEMU gate. Windows / Apple remain post-1.0. |
| Backends | Linux (**working**) · AGNOS (**working, validated**) · Windows / Apple (post-1.0) |
| Tests | **373** assertions in `tests/yo.tcyr`. `tests/yo.bcyr` (5 real benchmark rows) and `tests/yo.fcyr` both green. Gate is sound since 0.5.9 — all three entry points clamp a non-zero return to 1, closing the 256/512/768-failure wait-status truncation. |
| Build size | **152,704 B** (`.text` 144,088). 400 unreachable fns. ⚠ `CYRIUS_DCE=1` **NOPs** them (68,740 B) but does **not** shrink the file — the size is identical with and without it. For comparison, iputils `ping` is 155,160 B. |
| Speed | `-c 1 -n 127.0.0.1`, best of 3 × 100 runs: **yo 381 µs** vs iputils `ping` 458 µs — ~17% faster per invocation. Pure-path rows (`cyrius bench`): `icmp_checksum` 64 B **95 ns**, `icmp_build_echo_request` **197 ns**, `ipv4_parse` **52 ns**, `ipv6_parse` **291 ns**, `output_ipv4_to_buf` **86 ns**. |
| Iron-validation host | archaemenid (Beelink SER, AMD) |
| Family position | First entry in the network-tools family; sibling to `dig` and `whirl`, all three on the `taar` substrate |

## Current position

**Every planned backlog band is closed.** The AGNOS backend and iron validation
(planned as § 0.6.x / § 0.7.x) were achieved between 0.5.3 and 0.5.11; the `taar`
extraction (planned as § 0.8.x) landed early at 0.5.5 when `dig` became the real
second consumer. The bands were named for the version they were expected to land in,
so those labels no longer match their release — [`roadmap.md`](roadmap.md) now says so
rather than implying the work is pending.

**The open band is [`roadmap.md`](roadmap.md) § 0.6.x — deferred-work cleanup.** It was
assembled at 0.6.0 by sweeping `src/`, `tests/`, `scripts/`, `docs/` and the CI YAML
for deferred language: TODOs, `[cleanup:]` markers, "not yet", "planned", "future".
Everything found was either **stale** (fixed or deleted on the spot — `CLAUDE.md` and
`README.md` both still called the AGNOS backend "future", and `src/platform.cyr` said
"Today: Linux only" two lines above a note that the AGNOS branch had landed) or
**real but untracked**, in which case it is now a roadmap line rather than a comment
nobody reads. One deferred marker remains in `src/` by design — `src/dns.cyr:249`, the
IPv6-nameserver limitation — and it now names the roadmap item that tracks it.

Beyond that band, two things are genuinely open:

1. **The AGNOS QEMU smoke is still a manual gate.** CI gained `cyrius build --agnos`
   (plus `bench` and `fuzz`) at 0.6.0, so the AGNOS arm is at least *compiled* on every
   push — it previously was not, by anything. But `scripts/agnos-qemu-smoke.sh` needs
   sibling checkouts + QEMU + OVMF, so it stays local. Nothing automated proves the
   AGNOS backend still *runs*; only that it still builds.
2. **The "≤ 30 KB after DCE" size criterion is void as written** — cyrius's DCE NOPs
   rather than strips, so no flag yo controls can reach it. Either file a section-GC
   ask against cyrius or restate the criterion. Do not silently drop it.

## Verification — what is actually proven, and how

| Surface | Evidence | Gate |
|---|---|---|
| Linux ICMP v4 + v6, DNS both directions, scope IDs, v4-mapped | 373 unit assertions + live probes on archaemenid | `cyrius test`, automated |
| AGNOS backend **compiles** | `cyrius build --agnos` | **in CI since 0.6.0** |
| AGNOS backend **runs**, `icmp_echo`#55 round-trips | `scripts/agnos-qemu-smoke.sh` — boots agnos, types a probe over QMP `send-key`, asserts on serial. 2/2 replies, 0% loss against the SLIRP gateway; correctly FAILs against an unreachable address. ⚠ the `ttl=64` it prints is a literal from `_ag_icmp_pong`, not a measurement | manual — **not in CI** |
| AGNOS on real hardware | agnos **1.51.7** burn, 2026-07-02: `yo google.com` **4/4 at 0% loss**, real DHCP lease. (Earlier 1.45.16 burn: 2/4, 50% loss — an agnos RX-ring overflow, fixed in 1.45.17, not a yo defect.) | manual burn |
| aarch64 | ⚠ **builds clean and would be wrong.** `src/platform_linux.cyr` hardcodes x86_64 syscall numbers and the aarch64 stdlib peer has no `SYS_SENDTO`, so `44` would arrive as `fstatfs(2)`. yo ships x86_64 only, so this is latent — but a green `--aarch64` build must not be trusted. | none |

## Dependencies (current)

**stdlib** (`cyrius.cyml [deps].stdlib`, 11 leaves — unchanged since the CLI landed):

```
string fmt alloc io vec str syscalls assert bench args flags
```

`args` + `flags` arrived with the CLI. DNS (0.4.0) and IPv6 (0.5.x) added none — the
resolver and the v6 framing are built directly on `platform_*` and stay in-tree.
`cyrius deps` vendors these into the gitignored `lib/`, hash-locked in `cyrius.lock`
(27 files at the 6.5.35 pin).

**taar** (`cyrius.cyml [deps.taar]`) — **0.5.0**, `modules = ["dist/taar.cyr"]`.
`path = "../taar"` resolves local dev; `git` + `tag` is the published fallback. yo
consumes **one symbol**, `ipv4_parse`; the bundle's `socket`/`dns` modules ride along
and DCE out. The 0.6.x plan below is **done** — the extraction landed at 0.5.5.

## Family (all three consumers now real)

The substrate and both siblings exist; none of this is "planned" any more.

| Repo | Version | Cyrius pin | taar | Relationship |
|---|---|---|---|---|
| **taar** | 0.5.0 | 6.5.35 | — | Substrate. yo folded `src/ipv4.cyr` onto it at 0.5.5. |
| **dig** | 0.3.5 | 6.2.24 | 0.3.1 | DNS resolver. Second `ipv4` consumer — it forced the extraction. |
| **whirl** | 0.6.4 | 6.4.25 | 0.3.1 | curl/wget. Third consumer; uses taar's `socket` + `dns`, which yo does not. |

**Family drift**: as of 2026-08-26 yo is the *first* of the three to reach 6.5.35 and
taar 0.5.0 — `dig` and `whirl` still pin 6.2.24 / 6.4.25 and taar 0.3.1. That is fine
(taar's `ipv4_*` surface is stable across 0.3.1 → 0.5.0), but it means yo is the
canary: the migration evidence gathered here — zero stdlib removals or arity changes
across 6.2.24 → 6.5.35 for these 11 modules — applies to them too when they follow.
`whirl` carries the larger risk, since it pulls the crypto/TLS leaves yo does not.

## Kernel coupling (AGNOS backend only)

The AGNOS backend reaches ICMP through the sovereign kernel ABI; the Linux backend has
no AGNOS coupling at all (it goes to the host kernel via POSIX socket numbers). The
kernel logic lives in `agnos/kernel/core/net_icmp.cyr` (`icmp_ping` + `net_handle_icmp`,
split out of `net.cyr` in the 1.36.x refactor) and has been reachable from ring 3 since
**agnos 1.45.4**.

**The kernel chose the focused shape, and yo adapted to it** — `icmp_echo(dst_ip)`#55 is
one-shot: it sends, waits, and returns the RTT in one blocking call. So
`platform_agnos.cyr` collapses `_send_to + _recv` onto it and synthesises the reply
packet locally. The rationale and its costs are recorded in
[ADR 0002](../adr/0002-focused-kernel-icmp-syscall.md); the acceptance consequences in
[architecture note 001](../architecture/001-reply-acceptance-invariants.md).

`src/probe.cyr` and `src/dns.cyr` call this platform surface. Both backends implement
all of it; the right-hand column is what AGNOS actually does:

| Platform call | AGNOS implementation |
|---|---|
| `platform_icmp_open()` | returns a sentinel fd (900) — there is no socket |
| `platform_icmp_send_to(fd, addr, pkt, len)` | **stores** the request; nothing is sent yet |
| `platform_icmp_recv_ext(fd, buf, max, ttl_out)` | calls `sys_icmp_echo`#55, then synthesises the reply from the stored request. `ttl_out` gets a **nominal 64** — #55 does not surface the real TTL |
| `platform_icmp6_*` | **unavailable** (`-1`) — agnos has no ICMPv6 syscall, so yo's v6 path is inert there |
| `platform_resolve_ifindex(name)` | **0** — no ifindex concept exposed to ring 3 |
| `platform_udp_open / _send_to / _recv` | `sys_udp_bind` / `sys_udp_send` / `sys_udp_recv` (#51-53), listener-id based, non-blocking with a host-side deadline |
| `platform_read_file(path, buf, max)` | `sys_open` / `sys_read` / `sys_close` |
| `platform_set_recv_timeout_ms(fd, ms)` | stores the value for the **UDP** poll loop only. ⚠ It cannot affect ICMP: #55's ~3 s bound is fixed inside the kernel, so **`-W` is silently inapplicable on AGNOS** |
| `platform_now_us()` / `platform_sleep_ms(ms)` | `sys_uptime_ms`#40 × 1000 / `sys_sleep_ms`#41 |
| `platform_install_interrupt_watch()` | **unavailable** (`-1`) — no ring-3 signal infra, so Ctrl-C interruption is a host-only nicety |
| `platform_dns_server()` | `sys_net_dns_server` (`net_config`#61 field 3) — the DHCP-leased resolver, preferred over `/etc/resolv.conf` |

On Linux the same surface is POSIX: `IP_RECVTTL` + `recvmsg` cmsg walking for the real
TTL, `IPV6_CHECKSUM`/`IPV6_RECVHOPLIMIT` for v6, `SO_RCVTIMEO` for `-W`, and
`/sys/class/net/<name>/ifindex` for scope IDs.

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| Kernel ICMP tx/rx **counters** for `--diag` | agnos keeps no ICMP counters and exposes none to ring 3 (`net_config` has exactly 4 fields). `--diag` dumps the DHCP lease instead. | agnos |
| Section GC / true dead-code **stripping** | `CYRIUS_DCE=1` NOPs but does not strip, so the ≤30 KB v1.0 criterion is unreachable | cyrius |
| A configurable timeout on `icmp_echo`#55 | the ~3 s bound is fixed inside the kernel's `icmp_ping`, so yo's `-W` cannot be honoured on AGNOS | agnos |
| Family toolchain drift | `dig` (6.2.24 / taar 0.3.1) and `whirl` (6.4.25 / taar 0.3.1) trail yo's 6.5.35 / taar 0.5.0 | dig + whirl |

*Both former AGNOS gates are closed* — `cyrius/lib/args.cyr:99` gained its agnos branch
at cyrius 6.0.87/6.1.32, and `icmp_echo`#55 / UDP #51-54 / `net_config`#61 went ring-3
at agnos 1.45.4. Iron RX was proven well before either.

## Consumers

None yet. yo IS a leaf consumer of the kernel; nothing depends on yo today.

## Cross-references

- [`roadmap.md`](roadmap.md) — milestone plan through v1.0
- [`../adr/0001-per-backend-sovereignty.md`](../adr/0001-per-backend-sovereignty.md) · [`../adr/0002-focused-kernel-icmp-syscall.md`](../adr/0002-focused-kernel-icmp-syscall.md)
- [`../architecture/001-reply-acceptance-invariants.md`](../architecture/001-reply-acceptance-invariants.md) — why yo matches replies on type alone
- [`../guides/diagnosing-no-reply.md`](../guides/diagnosing-no-reply.md) — the `--diag` decision tree
- `cyrius/lib/args.cyr:99` + `cyrius/lib/args_agnos.cyr` + `cyrius/lib/syscalls_x86_64_agnos.cyr` — the agnos userland stdlib surface (the old gate #1 lived in args.cyr and is now closed; `syscalls_x86_64_agnos.cyr:1190` also offers `sys_net_dns_server()`, which yo adopted at 0.5.10 — `src/platform_agnos.cyr:139` now calls the wrapper, retiring the interim raw `syscall(61, 3)` that 0.5.7 shipped)
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
