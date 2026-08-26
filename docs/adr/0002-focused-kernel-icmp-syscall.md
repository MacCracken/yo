# 0002 — The AGNOS kernel ICMP syscall is focused, not general

**Status**: Accepted
**Date**: 2026-08-26

## Context

yo ships two backends (ADR 0001, per-backend sovereignty). The Linux backend reaches the host kernel through POSIX sockets by raw syscall number — `_LX_SYS_SOCKET = 41`, `_LX_SYS_SENDTO = 44`, `_LX_SYS_RECVMSG = 47` in `src/platform_linux.cyr` — against an unprivileged `AF_INET` / `SOCK_DGRAM` / `IPPROTO_ICMP` socket, falling back to `SOCK_RAW`. The AGNOS backend has no POSIX at all. It calls the sovereign ring-3 ABI through the cyrius `CYRIUS_TARGET_AGNOS` peer: `sys_icmp_echo` (#55), `sys_udp_bind`/`_send`/`_recv`/`_unbind` (#51–54), `sys_net_dns_server` (#61 field 3), `sys_uptime_ms` (#40), `sys_sleep_ms` (#41).

The ICMP logic predates the syscall. `icmp_ping(dst_ip)` has lived in `agnos/kernel/core/net_icmp.cyr:70` since the 1.36.x net split, with in-kernel callers only. When it was promoted to ring 3 it was promoted *as it was* — one call that sends, waits, and returns elapsed ticks. `agnos/kernel/core/syscall.cyr:9593` states the contract in full:

> `icmp_echo(dst_ip=arg1)` — send one ICMP echo request (ping) to `dst_ip` and block (~3 s bounded) for the matching reply; returns the round-trip time in MILLISECONDS (>= 0) or -1 (timeout / NIC down). […] RTT resolution is the 100 Hz tick (10 ms); a sub-10 ms reply returns 0. a2..a4 unused. (The ~3 s timeout is `icmp_ping`'s fixed bound; a configurable `-W` is a future enhancement that would parameterise `icmp_ping`.)

`docs/development/state.md` § Kernel coupling — written before the syscall existed, which is why it hedges — recorded the situation as still open: the AGNOS shape could mirror yo's `platform_*` surface 1:1, *or* the kernel could offer the focused form, and **"the kernel has already de-facto chosen the focused form"**. `roadmap.md` § 0.6.x now records the outcome: promoted at agnos 1.45.4, "the kernel kept the **focused** shape".

So the real choice is not what shape the kernel should invent. It is whether yo accepts the shape the kernel already has, or asks the kernel to grow toward the POSIX-like surface yo's probe path was written against. This ADR settles that, and writes down what accepting it costs.

## Decision

**AGNOS exposes ICMP echo as the one-shot `icmp_echo(dst_ip) -> rtt_ms` and nothing more; yo adapts to that shape in `src/platform_agnos.cyr` rather than asking the kernel to grow a POSIX-like socket/send/recv surface for it.**

Scope, precisely:

- **In**: the ICMP echo probe path on the AGNOS backend. `platform_icmp_open` returns a sentinel fd (`_AG_ICMP_FD = 900`, no real socket), `platform_icmp_send_to` stores the request, and `platform_icmp_recv_ext` collapses onto the single `sys_icmp_echo` call.
- **Out — not a kernel-wide doctrine.** yo's own DNS path on the same backend uses `sys_udp_bind`/`_send`/`_recv`/`_unbind` (#51–54), which *is* a bind/send/recv-shaped surface with buffers crossing the ring boundary. Focused-vs-general is decided per primitive against the workload, not declared once for the kernel.
- **Out**: ICMPv6. There is no v6 syscall; `platform_icmp6_open` returns `-1` and the backend reports the v6 path unavailable rather than silently lossy (`src/platform_agnos.cyr:153`).

## Consequences

### Positive

- **Minimal kernel surface.** #55 takes one `i64` and returns one `i64`. No pointer crosses the ring boundary on the ICMP path, so there is no per-process socket table, no fd lifetime, no buffer-ownership question, no partial-read semantics, and nothing to validate beyond a packed IPv4 address.
- **The evidence for this is in the same kernel.** AGNOS *does* have a more general socket surface — `sock_listen`#56 / `sock_accept`#57 — and it regressed exactly where generality costs: `syscall.cyr:9650` records that the 1.49.4 "socket-as-VFS-fd" wrap "silently BROKE the actual ring-3 socket API" (fixed at 1.53.9, per the same comment block — so this is evidence that generality is *easy to break silently*, not that it stays broken), because the only ring-3 consumer drove the return as a `conn_id`. A one-shot integer-in/integer-out call has no equivalent failure mode available to it.
- **The kernel keeps the retry/timeout policy, and the hard part stays where it works.** The blocking wait runs in the proven `sleep_ms`#41 sti-window — `preempt_disable()` + `sti` + `cli` + `preempt_enable()` (`syscall.cyr:9608-9612`) — so `timer_ticks` advances and `arch_wait()`'s halt wakes while the IRQ-less NIC is polled. A ring-3 send/recv pair does not remove that window; it either reproduces it inside a blocking `recv` anyway, or pushes a poll loop into ring 3 that has to be correct about the same invariant.
- **It works, on iron, not just in QEMU.** agnos CHANGELOG 1.51.7 (2026-07-02): real DHCP lease `192.168.1.195`, `net: L2 OK`, `yo google.com` 4/4 at 0% loss. The earlier 1.45.16 burn (`yo google.com` 2/4, 50% loss) was an RX-ring overflow fixed in 1.45.17 — a kernel RX-servicing bug, not a shape problem. `scripts/agnos-qemu-smoke.sh` (shipped 0.5.11) gates it: `10.0.2.2` → 2 sent / 2 received / 0% loss, and it correctly FAILs against an unreachable address. (Its `ttl=64` is the literal described in § 4, not evidence.)

### Negative

These are the price. All four are real, all four are visible in output yo prints today.

| Cost | Where it bites |
|---|---|
| `-W` is accepted and cannot be applied | `net_icmp.cyr:96` — `while ((timer_ticks - start) < 300)` |
| RTT floor is one 100 Hz tick | `syscall.cyr:9615` — `return ie_ticks * 10;` |
| The reply is synthesised host-side | `platform_agnos.cyr:59` — `_ag_icmp_pong` |
| `ttl=` is a nominal constant | `platform_agnos.cyr:72` — `store64(ttl_out, 64)` |

**1. `-W` cannot be honoured on AGNOS.** `probe.cyr:47` calls `platform_set_recv_timeout_ms(fd, timeout_ms)`; the AGNOS implementation (`platform_agnos.cyr:114`) stores it in `_ag_timeout_ms`, which is read only by `platform_udp_recv` — the DNS path. The ICMP path never reads it. The bound is the kernel's 300 ticks at 100 Hz, ~3 s, not parameterisable. The default `-W` is 1000 ms (`cli.cyr:27`), so on AGNOS a lost packet blocks roughly **three times the flag's own default**, and `yo -W 200` blocks fifteen times it. yo does not reject the flag and does not warn: `--diag`'s AGNOS block prints the `net_config`#61 fields and the raw `icmp_echo` return, and says nothing about `-W`. Whether it should warn is open; today it does not.

**2. RTT resolution is the tick, so `rtt=0.00 ms` is normal output.** Both clocks in play are the same 100 Hz counter: #55 returns `ticks * 10`, and `platform_now_us()` is `sys_uptime_ms() * 1000` where #40 returns `timer_ticks * 10` (`syscall.cyr:9057`). yo brackets `send_to..recv_ext` host-side with `platform_now_us` (`probe.cyr:77`, `probe.cyr:89`) and reports *that*, so the kernel's returned RTT is not actually the number printed — it is used only as a success/fail signal and stashed in `_ag_last_echo_rc` (`platform_agnos.cyr:40`) for `--diag`. Either way the floor is 10 ms. The 1.51.7 iron pass records it plainly: 4/4 at 0% loss "with three RTTs at sub-tick `0.00 ms`". A LAN or gateway probe on AGNOS genuinely prints zero.

**3. yo synthesises the reply packet.** `_ag_icmp_pong` calls `sys_icmp_echo`, and on success hands the *stored request* back as the reply — copy `_ag_req`, flip type 8 → 0, zero and recompute the RFC-1071 checksum with yo's own `icmp_checksum`, return the length; on failure it returns `-11`, mirroring `SO_RCVTIMEO`'s `EAGAIN` so the Linux and AGNOS failure paths converge.

Is that a smell or a legitimate adapter? Both readings have teeth.

*It is a smell.* The bytes yo "receives" never crossed a wire, and neither did the bytes yo built. The kernel constructs its own packet (`net_icmp.cyr:84-90`): type 8, identifier `icmp_id = 0x4147` ("AG"), the kernel's own incrementing `icmp_seq`, a fixed 32-byte `0x41 + (i & 0x0F)` payload, 40 bytes total. yo's ident `0x1234` (`probe.cyr:61`) and its `-s 56` default payload (`cli.cyr:29`) never leave the host. So on AGNOS `-s` changes the banner (`output.cyr:191`) and the buffer sizes and nothing on the network. A test asserting "yo put 56 payload bytes on the wire" would be asserting something false there.

*It is a legitimate adapter.* The alternative is a second probe loop. `probe.cyr` is one loop serving v4, v6, Linux and AGNOS, and it owns the accounting (`stats.cyr`), the output and the interrupt handling; forking it per backend duplicates all of that to accommodate one primitive. The bridge is twenty lines, it lives below `platform.cyr`'s `#ifdef` dispatch where an adapter belongs, and the divergence is confined to one function under a named comment block rather than smeared through the probe path.

**Position: legitimate adapter — with a hazard that has since fired, and is recorded here rather than papered over.**

When this ADR was drafted, the bridge satisfied a parser that barely checked: the probe path tested only `icmp_type(rxbuf) != expected_reply`, and `icmp_verify` (`icmp.cyr:70`) was — and still is — never called there, so the checksum recompute at `platform_agnos.cyr:70` satisfied no caller at all. It is kept because it makes the buffer a well-formed RFC-792 message.

The draft then warned: *"the day `probe.cyr` tightens to match ident and seq, the AGNOS path will pass that check for the wrong reason."* **That day was the same release.** 0.6.0 fixed a real defect in the Linux `SOCK_RAW` path (see [architecture note 001](../architecture/001-reply-acceptance-invariants.md)) and, as part of it, `probe.cyr:121` now matches `seq` unconditionally and `:126` matches `ident` on RAW.

So the hazard is live, and it is worth being exact about its shape:

- On **Linux** the new checks buy real confidence. The reply came off the wire; matching `seq` proves it belongs to *this* probe rather than a late one from probe *n-1*, and on RAW matching `ident` proves it is yo's rather than another process's.
- On **AGNOS** they buy nothing. `_ag_icmp_pong` hands back the request yo just stored, so `icmp_seq(rxbuf) == seq` and `icmp_ident(rxbuf) == ident` hold **by construction**. The checks are tautologies there. The bytes that actually crossed the wire carried the kernel's own ident (`0x4147` in the observed capture) and were validated inside `icmp_ping`; yo never sees them.

This is not a bug — the kernel did the matching, which is precisely the deal the focused syscall strikes (see § Consequences). But it means **the probe path's identity checks are not a shared guarantee across backends**: they are enforcement on Linux and decoration on AGNOS. Anyone strengthening them further — matching the payload, calling `icmp_verify` — must decide deliberately whether to bypass the bridge, extend it, or accept that the check is inert on that backend. The one thing not to do is read a green AGNOS run as evidence that the check works.

**4. The TTL yo reports on AGNOS is nominal.** `icmp_echo` surfaces no reply TTL — by the time the kernel sets `icmp_reply_seen` it has read only type and identifier from the ICMP header (`net_icmp.cyr:47-52`) and the IP header is gone. `_ag_icmp_pong` writes a flat `64`. `output_reply` prints the `ttl=` chunk whenever the value is greater than zero (`output.cyr:212`), so an AGNOS reply line is **typographically identical** to a Linux line carrying a real `IP_RECVTTL` cmsg value. The smoke script's recorded `ttl=64` is a constant, not a measurement. Reading an AGNOS `ttl=` as a hop count is reading a literal.

### Neutral

- `-W`, `-s` and a real TTL are now agnos-side asks, not yo-side work. yo already carries one such ask that went nowhere: `roadmap.md` § 0.7.x wanted kernel ICMP tx/rx counters in `--diag`, and `platform_agnos.cyr:184` records why they are absent — `net_config` has exactly four fields (0..3) and returns -1 for anything else, so the counters stay a kernel ask and `--diag` dumps what is reachable instead.
- The kernel names its own escape hatch. `syscall.cyr:9605` already flags a configurable `-W` as "a future enhancement that would parameterise `icmp_ping`". If `-W` ever becomes load-bearing on AGNOS, the intended next step is `icmp_echo(dst_ip, timeout_ms)` — one more argument, still one call — not a socket layer. Record that as the preferred move before anyone reaches for the general alternative below.
- **Unproven: concurrency.** `icmp_id`, `icmp_seq` and `icmp_reply_seen` are kernel globals (`net_icmp.cyr:12-15`) and the reply match is on **identifier only, not sequence** (`net_icmp.cyr:48`). One ping is in flight kernel-wide, and a stale reply carrying `0x4147` satisfies whatever wait is currently open. yo never exercises this — `main.cyr` walks targets sequentially and `probe.cyr` walks sequence numbers sequentially, so there has never been a second prober. This is stated as untested, not as broken: nothing has demonstrated a misattributed reply, and nothing has demonstrated it cannot happen.

## Alternatives considered

**A general `net_send_raw` / `net_recv_raw` pair.** `CLAUDE.md` § Goal still names this as the anticipated AGNOS shape — "sovereign `icmp_echo` / `net_send_raw` + `net_recv_raw` primitives". `roadmap.md` does not, and never asked for the pair by name: § 0.6.x asks only to promote `icmp_ping` and records that the kernel kept the focused shape. The two documents disagree; this ADR settles it in favour of the roadmap. § 0.6.x also shows what the general form was already costing in planning: the item "per-process ICMP listener registration in the agnos kernel" is struck as **obsolete** — "it presupposed a general send/recv surface", and a kernel that matches replies internally has no per-process listener to register. On the merits, the raw pair is the shape that fixes all four costs at once — packet construction moves to ring 3, so yo's ident, seq, payload and `-s` reach the wire, the reply is a real frame, its IP header carries a real TTL, and the timeout becomes yo's. It loses on what the kernel must then own: a per-process RX filter and queue so one process's frames do not leak to another, buffer ownership across the ring boundary in both directions, and a poll/wake path — while the sti-window problem does not go away, it just moves. Rejected on cost, for now, not on principle. It is the right escalation if a second ring-3 consumer needs raw frames; it is over-built for one tool sending one echo.

**A full POSIX socket layer in the AGNOS kernel.** Rejected. It is the largest available surface for the smallest available consumer, and it contradicts the kernel-grows-for-native-workloads rule — `roadmap.md` § v1.0 criteria carries "**No POSIX `socket()` in the AGNOS backend**" as a release gate, formalised in ADR 0001. The concrete argument is local: AGNOS's existing partial socket surface already broke its only ring-3 consumer once, silently, in 1.49.4 (`syscall.cyr:9650`).

**Mirroring yo's `platform_*` surface 1:1 in the ABI.** Raised in `state.md` § Kernel coupling as a live option — the kernel could expose exactly `platform_icmp_open` / `_send_to` / `_recv_ext`. Rejected: that surface is itself a POSIX artifact, shaped by `SO_RCVTIMEO` and `IP_RECVTTL` in `platform_linux.cyr`. Adopting it as the sovereign ABI imports POSIX through the back door and lets a leaf tool author a kernel interface. The Linux backend is a reference for what yo *needs*, not a template for what the kernel should *be*.

**Enforcing `-W` host-side — call #55 and abandon it after `timeout_ms`.** Rejected: it cannot be built. #55 blocks in the kernel, and there is no ring-3 way to interrupt it — AGNOS has no ring-3 signal infrastructure, which is why `platform_install_interrupt_watch` returns `-1` and `platform_check_interrupted` never fires (`platform_agnos.cyr:162`). A host-side timeout would need a timer and a cancellation path that do not exist. Parameterising the kernel's bound is the only real version of this.
