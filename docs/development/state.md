# yo — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md). Audits → [`../audit/`](../audit/).
>
> **Last refresh**: 2026-11-08 (unreleased, on 0.7.2: the AGNOS 0.8.x items — `-W` through `icmp_echo_ex`#100, ICMP counters in `--diag`, SIGINT). The position, verification and kernel-coupling sections were re-checked against the code and the agnos source for that work; the rest of the snapshot at 0.7.2, and the dependency and family facts at 0.7.1, the same day.

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.7.2** |
| Cyrius pin | 6.7.18 · taar dep 0.6.2 |
| Status | **Both shipping backends work and are validated, and the tree is audited.** Linux is at POSIX-ping output parity for v4 + v6. AGNOS reaches ICMP through the sovereign kernel surface, is iron-validated, and passes its QEMU smoke; since the unreleased 0.8.x work it honours `-W`, prints the kernel ICMP counters in `--diag`, and stops on SIGINT. The 0.7.2 P(-1) fixed 25 findings ([report](../audit/2026-11-08-audit.md)). Windows / Apple are v1 backlog. |
| Backends | Linux (**working**) · AGNOS (**working, validated**) · Windows / Apple (post-1.0) |
| Tests | **505** assertions in `tests/yo.tcyr`; **49** host guards mutation-checked (37 at 0.7.2, 12 for the 0.8.x AGNOS helpers; removing any one turns a suite red), and the AGNOS-only guards the host cannot reach mutation-checked through the QEMU smoke (§ Verification). `tests/yo.fcyr`: 20,000 deterministic fuzz rounds, 22 invariants, run plain and under `--poison`. `tests/integration/run.sh`: **28** end-to-end checks in a network namespace (0.7.1 fails 18). `tests/yo.bcyr`: 8 rows. Bare `cyrius test` also runs the `src/test.cyr` stub, so it reports 2 units. Exit codes are clamped to 1 (since 0.5.9). |
| Cleanliness | `cyrius audit` fully clean — fmt, lint, docs (every public fn documented) — and gated in CI. |
| Build size | **205,104 B** default (513 unreachable fns, 116,684 B). **86,320 B** with `CYRIUS_DCE=1`. AGNOS 215,968 B, or 88,992 B under DCE. (0.7.2: 200,936 / 86,248; AGNOS 215,144 / 84,072.) iputils `ping` is 155,160 B, so the DCE build is smaller and the default build is not; the 1.0 size criterion turns on which one releases ship (roadmap 0.10.x). |
| Speed | 0.6.0, best of 3 × 100 `-c 1 -n 127.0.0.1`: **yo 381 µs** vs iputils 458 µs. 0.7.2 under a bash loop on this host: 448–449 µs against 444–445 µs for 0.7.1. Bench medians: `icmp_checksum` 64 B 96 ns, `icmp_build_echo_request` 206 ns, `ipv4_parse` 54 ns, `ipv6_parse` 309 ns, `output_ipv4_to_buf` 85 ns, `probe_reply_is_ours` raw+cksum 116 ns, PTR parse + hostname check 183 ns, question echo 107 ns. |
| Iron-validation host | archaemenid (Beelink SER, AMD) |
| Family position | First entry in the network-tools family; sibling to `dig` and `whirl`, all three on the `taar` substrate |

## Current position

**0.7.2 closed the first P(-1) audit.** 25 findings, all fixed; the decisions and
feature work it surfaced are on the roadmap. What remains before 1.0 is three bands
([`roadmap.md`](roadmap.md)):

- **0.8.x — backend parity.** The three AGNOS items are done, unreleased on 0.7.2:
  `-W` through `sys_icmp_echo_ex`, ICMP counters through `sys_net_icmp_*`, and
  SIGINT through `sys_sigprocmask` / `sys_signalfd`. What they cannot do is the
  kernel's (§ Kernel coupling): agnos raises no signal from the console, and a
  signal cannot end a reply wait. Left in 0.8.x: aarch64-correct Linux syscalls
  (see § Verification), a gateway-literal iron run (which would also be the first
  iron run of #100), and AGNOS execution in CI.
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
| Linux ICMP v4 + v6, DNS both directions, scope IDs, v4-mapped, SOCK_RAW header strip, reply acceptance, CLI ranges, interruptible waits, no per-probe allocation | 505 unit assertions; 37 mutation-checked guards | `cyrius test` + `cyrius audit`, **in CI** |
| The AGNOS arm's decisions: the #100 echo bound (1 ms … 60 s), the #100 probe (field 4 = -1 → #55; 0 is a live kernel), the counter verdict, the sleep slice | pure helpers in `src/platform.cyr`, 22 assertions in the same suite; written failing-first (11 red), 12 mutations, 12 killed | `cyrius test`, **in CI** |
| Every byte parser (DNS, resolv.conf, ICMP frames, cmsg, IPv6 literals) | 20,000 fuzz rounds, 22 invariants, plain and under `--poison` (a heap overrun exits 86) | `cyrius fuzz`, **in CI** |
| The SOCK_RAW fallback (v4 + v6), Ctrl-C, multi-target stop, RSS over a long run, the seq wrap, DNS end to end (PTR injection, a forged reply, fail-closed resolv.conf, CRLF) | `tests/integration/run.sh`: 28 checks in an `unshare` network + mount namespace with a fake DNS server | **in CI** under `sudo unshare` since 0.7.2 — that branch had not yet run on GitHub at release |
| AGNOS backend **compiles** | `cyrius build --agnos` | **in CI** |
| AGNOS backend **runs** | `scripts/agnos-qemu-smoke.sh`: boots agnos, types probes over QMP `send-key`, asserts on serial. 2026-11-08, on a kernel built from the agnos working tree (VERSION 1.57.18, with uncommitted changes): 2/2 replies from the SLIRP gateway; `-s 3000` refused with EMSGSIZE; `-W 500` × 2 lost probes in **1077 ms**, timed in the guest; `--diag` showing `icmp tx: 2 this run` with rx unmoved and the "requests left this host" verdict; a SIGINT in a 2 s interval ending yo in **45 ms** with its summary; a SIGINT during the last reply wait stopping the run before the second target (the wait ran to -W, 1297 ms after the signal); no kernel fault. The SIGINTs come from `tests/agnos/yosmoke.cyr`, yo's parent in the guest. **AGNOS-side mutations, through the smoke:** #55 only (6085 ms), no post-loop check (second target started), totals for deltas, one shared bound (2084 ms), an unsliced sleep (824 ms), no watch (55 s, 30 sent): 6 of 6 killed. ⚠ the `ttl=64` it prints is a literal from `_ag_icmp_pong`, not a measurement | manual — needs the agnos / gnoboot / agnoshi checkouts, QEMU and OVMF |
| AGNOS on real hardware | agnos **1.51.7** burn, 2026-07-02: `yo google.com` **4/4 at 0% loss**, real DHCP lease. A gateway-literal run is not separately recorded, and the 0.8.x paths (#100, the counters, SIGINT) have not run on iron; 1.51.7 predates #100, so a new yo there takes the #55 fallback (roadmap 0.8.x) | manual burn |
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

**The kernel chose the focused shape, and yo adapted to it** — the echo is one-shot:
`icmp_echo_ex(dst_ip, timeout_ms)`#100 (agnos ≥ 1.56.48; `icmp_echo(dst_ip)`#55,
with a fixed ~3 s bound, before that) sends, waits, and returns the RTT in one
blocking call. So `platform_agnos.cyr` collapses `_send_to + _recv` onto it and
synthesises the reply packet locally. yo picks the arm once per process:
`net_config`#61 field 4 (`icmp_tx`) arrived in the same agnos commit as #100, and
an older kernel answers -1 to both. #100's -1 would read as a timeout, so the
probe is what keeps a new yo working on, for example, the 1.51.7 kernel it was
iron-validated on. The rationale and its costs are in
[ADR 0002](../adr/0002-focused-kernel-icmp-syscall.md); the acceptance consequences in
[architecture note 001](../architecture/001-reply-acceptance-invariants.md).

`src/probe.cyr` and `src/dns.cyr` call this platform surface. Both backends implement
all of it; the right-hand column is what AGNOS does:

| Platform call | AGNOS implementation |
|---|---|
| `platform_icmp_open()` | returns a sentinel fd (900) — there is no socket |
| `platform_icmp_send_to(fd, addr, pkt, len)` | **stores** the request (at most 2048 B; a longer one is refused with -EMSGSIZE); nothing is sent yet |
| `platform_icmp_recv_ext(fd, buf, max, ttl_out)` | calls `sys_icmp_echo_ex`#100 with -W as the bound (clamped to the kernel's 1 ms … 60 s), or `sys_icmp_echo`#55 on a kernel without #100, then synthesises the reply from the stored request. `ttl_out` gets a **nominal 64** — neither arm surfaces the real TTL |
| `platform_wait_readable` | "readable" at once: the wait happens inside the echo. ⚠ **No signal ends that wait** (an agnos signal is a pending bit and wakes no kernel wait; only kill 9 / stop do), so a SIGINT during it is seen when the echo returns, at the reply or at -W |
| `platform_sleep_interruptible(sigfd, ms)` | `sys_sleep_ms`#41 in slices of at most 50 ms (`PLATFORM_SLEEP_SLICE_MS`) against an absolute deadline, reading the signalfd before each; a SIGINT ends it within ~one slice |
| `platform_icmp6_*` | **unavailable** (`-1`) — agnos has no ICMPv6 syscall, so yo's v6 path is inert there |
| `platform_resolve_ifindex(name)` | **0** — no ifindex concept exposed to ring 3 |
| `platform_udp_open / _send_to / _recv` | `sys_udp_bind` / `sys_udp_send` / `sys_udp_recv` (#51-53), listener-id based, non-blocking with a host-side deadline. The kernel delivers by destination port alone, so `_recv` drops datagrams whose source is not the recorded peer (`platform_peer_match`) |
| `platform_random_u16()` | `sys_getrandom`#45, degrading to the clock if it fails |
| `platform_read_file(path, buf, max)` | `sys_open` / `sys_read` / `sys_close` |
| `platform_set_recv_timeout_ms(fd, ms)` | per fd, as `SO_RCVTIMEO` is on Linux: on the ICMP sentinel it is -W, which #100 enforces in the kernel; on a UDP listener the DNS poll deadline |
| `platform_now_us()` / `platform_sleep_ms(ms)` | `sys_uptime_ms`#40 × 1000 / `sys_sleep_ms`#41 |
| `platform_install_interrupt_watch()` / `_check_interrupted` / `_remove_interrupt_watch` | `sys_sigprocmask`#17 SIG_BLOCK on SIGINT, then `sys_signalfd`#18; the check is a non-blocking `sys_read_nb` of the signalfd; remove closes it and unblocks. The set comes from the stdlib's agnos `sigset_add` (agnos sets are `1 << sig`, not Linux's `1 << (sig - 1)`). ⚠ **No console key raises SIGINT on agnos** (agnos-userland-abi.md § 4.9), so Ctrl-C at the keyboard reaches no one; the signal must come from `kill`#16, which only yo's parent, yo itself or init may send |
| `platform_diag_reset()` / `platform_diag_dump()` | the address fields (`net_config`#61 fields 0..3) and the ICMP counters (fields 4..7, agnos ≥ 1.56.48): sampled at reset, printed as `N this run (M since boot)`, read by `platform_icmp_verdict` into "nothing left this host" / "sent, nothing came back" / "another process was pinging" |
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
| A single-wait interval sleep on AGNOS | The kernel's `epoll_wait`#21 has a timed form since 1.57.17 (`max` bit 32, timeout in a4), and an ordinary signal wakes it. The vendored `sys_epoll_wait` is the 3-argument poll and cannot set a4, so yo slices `sleep_ms`#41 instead. A timed wrapper would make the sleep one wait on the signalfd. Optional: the slices cost ≤ ~50 ms of latency | cyrius |

## Consumers

None yet. yo IS a leaf consumer of the kernel; nothing depends on yo today.

## Cross-references

- [`roadmap.md`](roadmap.md) — the plan through v1.0 and the v1 backlog
- [`../audit/2026-11-08-audit.md`](../audit/2026-11-08-audit.md) — the 0.7.2 P(-1): findings, method, deferred items
- [`../adr/0001-per-backend-sovereignty.md`](../adr/0001-per-backend-sovereignty.md) · [`../adr/0002-focused-kernel-icmp-syscall.md`](../adr/0002-focused-kernel-icmp-syscall.md)
- [`../architecture/001-reply-acceptance-invariants.md`](../architecture/001-reply-acceptance-invariants.md) — what yo checks before believing a reply
- [`../guides/diagnosing-no-reply.md`](../guides/diagnosing-no-reply.md) — the `--diag` decision tree
- `agnos/kernel/core/net_icmp.cyr` (`icmp_ping_us`, `net_handle_icmp`) + `agnos/kernel/core/syscall.cyr` (`num == 55`, `num == 100`, `num == 61`) — the kernel ICMP logic, the two ring-3 echo arms and the counters. Read the #55 / #100 comment blocks for the contract: RTT in ms, #55's fixed ~3 s bound, #100's caller bound clamped to 60 s and never early.
- `agnos/docs/development/agnos-userland-abi.md` § 4.9 — signals on agnos: `1 << sig` sets, no default action outside 9 / 18 / 19, no console signal.
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
