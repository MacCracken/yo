# 0001 — Per-backend sovereignty

**Status**: Accepted
**Date**: 2026-08-26

## Context

yo probes ICMP against two kernels that do not agree on what a network operation is.

**Linux** offers the POSIX socket family. yo uses four of its verbs — `socket`, `sendto`,
`recvmsg`, `setsockopt` — plus the options that make a usable `ping`: `SO_RCVTIMEO` for
`-W`, `IP_RECVTTL` / `IPV6_RECVHOPLIMIT` to surface the reply TTL as ancillary data, and
`IPV6_CHECKSUM` so the kernel fills the ICMPv6 checksum and yo needs no pseudo-header math.
The unprivileged `SOCK_DGRAM` + `IPPROTO_ICMP` "ping socket" is what lets `yo 1.1.1.1` run
as a normal user; `SOCK_RAW` is the root fallback (`src/platform_linux.cyr:86-99`).

**AGNOS** offers none of that. Its ring-3 ICMP surface is one syscall,
`icmp_echo`#55 (`agnos/kernel/core/syscall.cyr:9593-9616`), and it is one-shot: it sends a
single echo request, blocks on a fixed ~3 s bound inside the kernel's `icmp_ping`, and
returns the round-trip time in **milliseconds** (≥ 0) or `-1`. There is no fd, no timeout
argument, no reply buffer, no TTL. RTT resolution is the 100 Hz tick — 10 ms — so a
sub-10 ms reply returns 0, which is why real agnos runs print `rtt=0.00 ms`.

A project whose stated point is sovereignty could plausibly have collapsed this in either
direction, and both collapses are coherent:

- **Refuse POSIX everywhere.** Write the Linux probe against `SOCK_RAW`/`AF_PACKET` only,
  or hand-frame below the socket layer, so that no `socket()` with POSIX semantics appears
  anywhere in the tree. The cost is that it buys nothing: on Linux you are calling the
  Linux kernel regardless, and the only question is which door. That door forfeits the
  unprivileged path (every invocation then needs root or `CAP_NET_RAW`) and forfeits
  `SO_RCVTIMEO`, the TTL cmsg, and the kernel-side ICMPv6 checksum — all of which yo
  currently relies on. It also would have delayed the Linux MVP behind purity work, which
  is exactly what the 2026-05-23 multi-backend pivot existed to stop.
- **Shim POSIX over agnos.** Implement `socket()` / `sendto()` / `recvfrom()` in userland
  on top of `icmp_echo`, so one code path serves both kernels. The cost is that the shim
  has nothing true to say: there is no socket object on that kernel, so the layer must
  invent an fd table, an errno space, and a `recvfrom` that corresponds to no receive. Its
  natural end state is asking agnos to grow a POSIX socket surface for one tool, which the
  kernel-growth rule refuses — agnos grows *focused primitives for native workloads*, and
  `icmp_ping(dst_ip) → rtt_ticks` is the shape it already chose for exactly that reason
  (`docs/development/roadmap.md` § 0.6.x: "NOT POSIX `socket()`").

The v1.0 gate already names the rule as a release criterion — "No POSIX `socket()` in the
AGNOS backend" (`docs/development/roadmap.md` § v1.0 criteria). This ADR is the reasoning
behind that line, written after both arms exist and both have run.

## Decision

**Sovereignty is enforced per backend, not project-wide.** The AGNOS backend uses only
sovereign agnos ring-3 syscalls — no POSIX, no `socket()`. The Linux backend uses the host
kernel's POSIX socket surface pragmatically.

### Where the boundary is

`src/platform.cyr` is the seam, and it is the whole seam — an 18-line `#ifdef`:

```
#ifdef CYRIUS_TARGET_AGNOS
include "src/platform_agnos.cyr"
#endif
#ifndef CYRIUS_TARGET_AGNOS
include "src/platform_linux.cyr"
#endif
```

Exactly one backend file is compiled. There is no runtime dispatch and no shared
abstraction layer between them. Both files define the same **21-function `platform_*`
surface** (`platform_icmp_open` … `platform_diag_dump`); everything above the seam —
`icmp.cyr`, `ipv4`/`ipv6` parsing, `dns.cyr`'s wire codec, `output.cyr`, `stats.cyr` —
is pure and shared.

### What "pragmatic" means on Linux

It means POSIX **semantics**, not libc. `src/platform_linux.cyr` is self-contained raw
syscalls: `_LX_SYS_SOCKET = 41`, `_LX_SYS_SENDTO = 44`, `_LX_SYS_RECVMSG = 47`,
`_LX_SYS_SETSOCKOPT = 54` (`:26-32`), invoked through `syscall(...)` directly. No libc is
linked and no C runtime is in the binary. The pragmatism is about accepting the host
kernel's ABI *shape*; it is not about borrowing someone else's runtime. yo is statically
self-contained on both arms — only the ABI underneath differs.

### What the AGNOS backend actually calls

| Path | Syscall |
|---|---|
| ICMP probe | `sys_icmp_echo` (#55) |
| DNS transport | `sys_udp_bind` / `_send` / `_recv` / `_unbind` (#51-54) |
| Resolver address | `sys_net_dns_server` — `net_config`#61 field 3 |
| Clock / pacing | `sys_uptime_ms` (#40), `sys_sleep_ms` (#41) |
| Entropy (source port) | `sys_getrandom` (#45) |

`platform_icmp_open` returns the sentinel `900` (`src/platform_agnos.cyr:44`) because no
socket object exists to open. As of 0.5.10 there are no bare syscall numbers left in that
file either — cyrius 6.5.35 ships the wrappers, and the last literal (`syscall(61, 3)`)
was retired precisely because #61 is `net_config` on AGNOS and `wait4(2)` on Linux.

### The bridge stays below the seam

yo's internal platform surface is POSIX-*shaped* (`open` → `send_to` → `recv_ext`). On
AGNOS that shape is a local convention, not a POSIX dependency. `platform_icmp_send_to`
stores the request; `_ag_icmp_pong` (`src/platform_agnos.cyr:59-74`) calls `icmp_echo`
once and then synthesises the reply by handing the stored request back with type flipped
8 → 0 and the RFC 1071 checksum recomputed by yo's own `icmp_checksum`, so yo's parser
sees a valid echo-reply matching its own id/seq/payload. RTT is measured host-side across
`send_to`..`recv_ext`, bracketing the blocking `icmp_echo`. TTL is a nominal 64 (`:72`)
because `icmp_echo` does not surface one. Every line of that bridge is inside the backend
file; nothing above the seam knows it happened.

The rule extends to the substrate: `lib/taar.cyr` carries the same split internally
(`:161` `#ifndef CYRIUS_TARGET_AGNOS` for the POSIX socket family, `:300` `#ifdef` for the
sovereign `sock_*` / `udp_*` path), so taar's POSIX half is never emitted on the agnos
target.

## Consequences

### Positive

- **Linux shipped instead of waiting.** The unprivileged `SOCK_DGRAM` path, the `SOCK_RAW`
  fallback, TTL via cmsg, and `-W` via `SO_RCVTIMEO` all came free from POSIX. None of
  them exist on agnos, and none of them had to be invented to get a working `ping`.
- **The AGNOS path stays honest.** No shim, no fake fds, no pressure on the agnos kernel
  to grow a socket layer it does not want.
- **The audit is scoped and cheap** — one file, 21 functions, and `grep socket
  src/platform_agnos.cyr` is the whole check.
- **Both arms are proven, not asserted.** Linux: 373/373 assertions green, plus iron use.
  AGNOS: two manual iron burns recorded in agnos's CHANGELOG (1.45.16 — `yo google.com`
  2/4 = 50% loss on an RX-ring overflow, fixed in 1.45.17; 1.51.7 on 2026-07-02 — 4/4 at
  0% loss), and yo 0.5.11's `scripts/agnos-qemu-smoke.sh` against the SLIRP gateway
  10.0.2.2: `2 sent · 2 received · 0% loss`. (Not `ttl=64` — that field is a
  literal on this backend, see ADR 0002 § 4.)

### Negative

- **The platform surface is duplicated.** 21 functions × 2 files; `platform_linux.cyr` is
  24,097 B, `platform_agnos.cyr` 9,528 B. A new `platform_*` entry point must be written
  twice, and a bug fixed in one is not fixed in the other. `--diag` is the sharpest case:
  two entirely independent `platform_diag_dump` implementations printing disjoint field
  sets, because the two kernels have disjoint things to say —

  ```
  --- diag: no reply from 192.0.2.1 (IPv4) ---
  backend         : linux (POSIX socket)
  icmp socket     : SOCK_DGRAM (unprivileged)
  ping_group_range: 0 2147483647
  last sendto     : ok (packets left the host)
  last recv       : -11 EAGAIN (timeout — sent, nothing came back within -W)
  ```
  ```
  --- diag: no reply from 10.0.2.99 (IPv4) ---
  backend         : agnos (sovereign syscalls)
  net ip          : 10.0.2.15
  netmask         : 255.255.255.0
  gateway         : 10.0.2.2
  dns server      : 10.0.2.3
  icmp_echo #55   : -1 (timed out at the kernel's fixed ~3 s bound, or NIC down)
  ```

- **The host build cannot exercise the AGNOS arm at all.** The `#ifdef` excludes it, so
  `cyrius build` never compiles `src/platform_agnos.cyr` and `cyrius test` never reaches
  it: of the 373 assertions in `tests/yo.tcyr`, **zero** reference the AGNOS backend
  (`grep -c 'platform_agnos\|_ag_' tests/yo.tcyr` → 0). The only two things that touch
  that arm are `cyrius build --agnos src/main.cyr build/yo-agnos` (proves it assembles)
  and `scripts/agnos-qemu-smoke.sh` (proves it runs). Since 0.6.0
  `.github/workflows/ci.yml` runs the first of those on every push, so a **compile**
  regression in the AGNOS arm is now gated. The smoke is not wired in and will not be:
  it needs sibling checkouts plus QEMU and OVMF, and it SKIPs with exit 0 when they are
  absent, so on a stock runner it would read as coverage that does not exist.
  **A RUNTIME regression in the AGNOS backend is still caught by a human on
  archaemenid or it is not caught.**

- **Semantics diverge, and yo does not paper over it.** `-W` is not honoured on the AGNOS
  probe path: `platform_set_recv_timeout_ms` stores `_ag_timeout_ms`
  (`src/platform_agnos.cyr:119-122`), but that value is read only by `platform_udp_recv`
  (`:97`) — `icmp_echo`'s ~3 s bound lives inside the kernel and takes no argument
  (`agnos/kernel/core/syscall.cyr:9605-9606`). Nor is that the only gap: `platform_icmp6_*`
  return `-1` because there is no ICMPv6 syscall (`:153-155`), `platform_resolve_ifindex`
  returns 0 because ring 3 sees no interface index (`:158`), and the Ctrl-C interrupt watch
  reports unavailable because there is no ring-3 signal infra (`:162-163`). The AGNOS
  backend is a real backend with a smaller feature set, not a parity backend.

- **The v1.0 audit obligation falls only on the AGNOS path.** The gate reads: "No POSIX
  `socket()` in the AGNOS backend (`src/platform_agnos.cyr`) … Audit pass per
  first-party-standards § Security Hardening covers the AGNOS path only." So the `socket()`
  calls at `src/platform_linux.cyr:87`, `:93`, `:271`, `:339`, `:345` are permanently
  exempt **by rule** — not by oversight. A reviewer grepping the tree will hit them; this
  ADR is the answer they get.

### Neutral

- Windows and Apple backends (post-1.0) inherit the pragmatic side by default: they are
  host kernels, so they get the Linux treatment. The rule only bites on AGNOS.
- Every future agnos kernel primitive is a yo-side simplification waiting to happen. If
  `icmp_ping` ever takes a timeout parameter, `-W` becomes honourable and `_ag_timeout_ms`
  becomes real on the ICMP path; if the reply TTL is ever surfaced, `:72`'s nominal 64
  goes away. ICMP tx/rx counters for `--diag` were asked for in roadmap § 0.7.x and remain
  a kernel ask — `net_config` has exactly fields 0..3 and returns -1 for anything else.
- **Size is not the argument for either side.** The host build is 152,704 B against
  `/usr/bin/ping` (iputils 20250605) at 155,160 B; `.text` is 145,232 B; the agnos build
  is 150,312 B. `CYRIUS_DCE=1` reports "400 unreachable fns (68740 bytes NOPed)" and the
  file is still exactly 152,704 B — NOPed, not removed. This decision buys correctness of
  posture, not bytes.

## Alternatives considered

**A POSIX shim over agnos** (one probe path, `socket()`/`sendto()`/`recvfrom()`
reimplemented on top of `icmp_echo`). Rejected. The shim has no truth to tell: there is no
socket object on that kernel — `platform_icmp_open` returns a sentinel *because* there is
nothing to open — so the layer would have to fabricate an fd table, an errno space, and a
receive that corresponds to no kernel receive. It also inverts the kernel-growth rule: the
natural pressure release is to make agnos grow a POSIX socket surface serving exactly one
tool, when the kernel already picked the focused shape (`icmp_ping(dst_ip) → rtt_ticks`)
on purpose. The bridge we do have (`_ag_icmp_pong`) is 16 lines and lives below the seam;
a shim would be a permanent compatibility layer above it.

**Sovereign-everywhere on Linux** (refuse `socket()`, hand-frame over a raw path).
Rejected. It is purity theatre against a kernel that is not ours: yo calls Linux either
way, and choosing the less-supported door costs the unprivileged `ping_group_range` path
(root or `CAP_NET_RAW` for every invocation), `SO_RCVTIMEO`, the `IP_TTL` /
`IPV6_HOPLIMIT` cmsg chain that `--diag` and the per-packet `ttl=` chunk are built on, and
the kernel-side ICMPv6 checksum fill. Sovereignty means *our* kernel does not depend on
someone else's design; it does not mean pretending the host kernel is ours.

**A tagged-union net abstraction** (a shared `lib/net.cyr`-style surface with one call site
and result unions dispatching per platform). Rejected, and both backend files say so in
their own headers. `src/platform_linux.cyr:3-6`: "the `lib/net.cyr` surface covers TCP/UDP
but not ICMP / sendto / recvfrom, and it wraps results in tagged unions that this thin
backend doesn't need." `src/platform_agnos.cyr:5-6` repeats the posture: "no POSIX, no
`lib/net.cyr` tagged unions." A shared type would have to be the union of two kernels that
barely overlap — there is no honest common shape covering both an fd-bearing `recvmsg`
with an ancillary cmsg chain and a one-shot call that returns an integer RTT and owns no
handle. The `#ifdef` is the cheaper seam and costs nothing at runtime. Duplication is the
price, and it is paid knowingly.

**One binary dispatching at runtime** — noted only so a future reader does not re-ask: it
is not possible here. A binary emitted for the agnos target cannot issue Linux syscall 41,
and the reverse holds too. The `#ifdef` is not a preference over runtime dispatch; runtime
dispatch was never on the table.
