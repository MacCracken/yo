# yo — Roadmap

> **Status**: Active | **Last Updated**: 2026-05-23
>
> Milestone path from scaffold (0.1.0) through v1.0 (full `ping` parity + LAN-on-iron). Per first-party-documentation roadmap shape: **Completed** / **Backlog** / **Future** / **v1.0 criteria**.
>
> Volatile state (binary size, test count, current cycle) lives in [`state.md`](state.md). This file is the milestone plan; state.md is the live snapshot.

---

## Completed

| Version | Landed | Items |
|---|---|---|
| **0.1.0** | 2026-05-23 | Initial `cyrius init` scaffold. README + CLAUDE.md + LICENSE + CHANGELOG + cyrius.cyml + tests/yo.{tcyr,bcyr,fcyr} + `.github/workflows/{ci,release}.yml`. Stub `main.cyr` prints `hello from yo`. Stdlib vendored in `lib/` (79 modules incl. `net.cyr`). |

---

## Backlog — path to v1.0

Ordered by dependency. Items further down depend on items earlier.

### 0.3.x — Linux MVP (single-host, single-shot) ✅ landed (unreleased)

**Not blocked on agnos.** Per the platform-pivot (2026-05-23), yo ships a Linux backend first via POSIX socket() under `src/platform_linux.cyr`; the AGNOS backend slots in later as a sibling file. Substrate extraction (`taar`) waits for a second consumer (dig) to drive it — yo absorbs everything inline for now.

- [x] `src/main.cyr` argument parsing via `lib/args.cyr` and `lib/flags.cyr` (-c -W -i -s -q -v -h).
- [x] IPv4 address parsing (`a.b.c.d`); IPv6 deferred to 0.4.x.
- [x] RFC 792 ICMP framing + RFC 1071 checksum (`src/icmp.cyr`).
- [x] RTT accumulator + summary format (`src/stats.cyr` + `src/output.cyr`).
- [x] Linux backend: unprivileged SOCK_DGRAM ICMP with SOCK_RAW fallback (`src/platform_linux.cyr`).
- [x] Probe loop: per-packet send/recv with SO_RCVTIMEO, sleep between iterations (`src/probe.cyr`).
- [x] Per-packet output (`seq=N rtt=X.XX ms` / `seq=N timeout`) + summary; POSIX exit codes (0 / 1 / 2).
- [ ] Ctrl-C signal handler → flush summary, exit per POSIX. Currently Ctrl-C kills mid-loop without summary.
- [ ] DNS resolution path. Will roll into yo inline; extraction to `taar` waits for `dig` to grow into a real consumer per [[project_tools_stable_ideas]].

### 0.2.x — AGNOS backend (kernel-side, in `agnos`)

**Reframed**: no longer the gate for yo MVP. yo runs on Linux today; this lands the AGNOS backend as a sibling to `src/platform_linux.cyr`. Still blocked on r8169 RX-path 5-part bundle iron-validating (Attempt 97 pending; see [agnosticos iron-nuc-zen-log](https://github.com/MacCracken/agnosticos/blob/main/docs/development/iron-nuc-zen-log.md)).

- [ ] Cyrius-native syscall surface in `agnos/kernel/core/net.cyr`. Per [[project_agnos_kernel_growth_rules]] — NOT POSIX `socket()`; either focused `icmp_echo(addr, timeout) → rtt_us` or the general `net_send_raw` + `net_recv_raw` pair. Shape decided by what yo's Linux backend ended up needing, now that we have a concrete reference.
- [ ] ICMP echo framing + RFC 792 checksum verification kernel-side (yo's `src/icmp.cyr` is the byte-for-byte reference).
- [ ] Per-process ICMP listener registration (analogous to UDP listener table at `net.cyr:142-196`).
- [ ] QEMU smoke: `qemu-net-icmp-smoke.sh` boots kernel + sends a self-loopback ICMP echo, asserts rtt > 0.
- [ ] `src/platform_agnos.cyr` in yo, dispatched by `#ifdef CYRIUS_TARGET_AGNOS` in `src/platform.cyr`.

- [ ] `src/main.cyr` argument parsing via `lib/args.cyr` and `lib/flags.cyr`. Flags: `-c <count>` (default 4), `-W <timeout_ms>` (default 1000), `-i <interval_ms>` (default 1000), `-s <payload_bytes>` (default 56), `-q` (quiet, summary only), `-v` (verbose, per-packet detail).
- [ ] DNS resolution path. **Decision point**: stays in `yo` as a vendored `taar.dns` shim until `dig` arrives, OR drives the `taar` extraction immediately. Per [[project_tools_stable_ideas]] memory, the three-consumer brainstorm (yo + whirl + dig) justifies extracting `taar` from cycle-open. Leans toward immediate extraction.
- [ ] IPv4 address parsing (`a.b.c.d`); IPv6 deferred to 0.4.x.
- [ ] Single-packet RTT measurement using `clock_gettime`-equivalent Cyrius syscall.
- [ ] Per-packet output format matching the README's example block (`seq=N  rtt=X.XX ms`).
- [ ] Ctrl-C signal handler → print summary block, exit 0 if any packets received, exit 1 if 100% loss.

### 0.4.x — Robustness

- [ ] IPv6 support (`yo ::1`, `yo fe80::...`). Requires kernel-side IPv6 ICMP framing — coordinate with the same kernel-net cycle that adds DHCPv6 if/when that lands.
- [ ] Reverse DNS lookup for the resolved address (display in the banner: `yo google.com (142.250.x.x)`). Requires `taar.dns` reverse-record path.
- [ ] Multiple targets (`yo router gateway 8.8.8.8`) — parallel probes with consolidated summary.
- [ ] TTL / hop-limit display in per-packet output (read from response ICMP header).
- [ ] Stable exit codes per POSIX `ping`: 0 = at least one reply, 1 = no replies but no error, 2 = error.

### 0.5.x — Iron validation

**Blocked on**: r8169 RX-path 5-part bundle iron-validating at Attempt 97 (currently pending — code landed, burn pending user authorization).

- [ ] First iron run: `yo 192.168.1.1` on archaemenid. Expected: RTT ≤ 1 ms against the home gateway.
- [ ] First WAN run: `yo 8.8.8.8`. Expected: RTT in the 5-30 ms range from a US residential connection.
- [ ] First-fail diagnostics: when 100% loss, dump kernel ICMP send / recv counters via a `--diag` flag (matches `read-boot-log.sh` pattern for r8169 CMOS slots).

### 0.6.x — `taar` extraction

**Trigger**: arrival of `whirl` or `dig` as a second consumer of the network primitives.

- [ ] Move `net_send_raw` / `net_recv_raw` / ICMP framing helpers / DNS resolution out of `yo` and into a standalone `taar` repo at `~/Repos/taar`. Per the substrate-lib extraction pattern in `feedback_dep_lockin_sandhi_unlock`.
- [ ] Add `taar = { path = "../taar" }` (or equivalent) to `yo/cyrius.cyml [deps]`.
- [ ] Add the same dep line to `whirl/cyrius.cyml` and `dig/cyrius.cyml` as those repos open.
- [ ] Bump `yo` to consume `taar` without API change (the extraction is internal — `yo`'s CLI surface stays stable).

---

## Future (post-1.0)

Lower priority. Item shape pinned for orientation; specific versions TBD.

- [ ] **Flood mode** (`yo -f`) — POSIX `ping -f` equivalent. Send packets as fast as the host can. Useful for stress-testing the kernel's network stack.
- [ ] **Timestamp option** (`yo -D`) — RFC-style timestamps per packet, for piping into log aggregators.
- [ ] **Bind-source-address** (`yo -I <iface_or_ip>`) — choose source interface. Useful when archaemenid has both `enp1s0` (wired) and `wlan0` (wireless) leases active.
- [ ] **Path-MTU discovery probe** (`yo -M do`) — set DF flag, walk MTU range. Useful for diagnosing tunnel / VPN MTU issues.
- [ ] **JSON output** (`yo --json`) — machine-readable summary for piping into other tools (`sutra`, `aegis`, `phylax` audit chains).
- [ ] **Audit-chain integration** — when `libro` lands, log every `yo` invocation + result to the audit chain. Forensic value: *"who pinged what, when, with what outcome."*

---

## v1.0 criteria (release gate)

Ship 1.0 when all of these are true. Pre-1.0 minor cycles can land partial subsets; the v1.0 tag is the all-of-these gate.

- [ ] **Feature parity with POSIX `ping`**: `-c`, `-W`, `-i`, `-s`, `-q`, `-v`, `-f`, `-D`, `-I`, `-M do`, IPv4 + IPv6, DNS resolution, reverse-DNS display.
- [ ] **`taar` extracted** as a separate repo. `yo` depends on `taar`; the kernel network primitives are not vendored back into `yo`.
- [ ] **LAN-on-iron validated** on archaemenid against the home gateway (`192.168.1.1`) and at least one WAN host (`8.8.8.8`).
- [ ] **QEMU + localhost validated** via `scripts/qemu-smoke.sh` — boots a kernel with yo in the initrd, pings 127.0.0.1, asserts RTT > 0 and < 5 ms.
- [ ] **No POSIX `socket()` in the AGNOS backend** (`src/platform_agnos.cyr`). Sovereign kernel primitives only on that path. The Linux backend (`src/platform_linux.cyr`) uses POSIX socket() pragmatically — this is intentional per the per-backend sovereignty rule. Audit pass per [first-party-standards § Security Hardening](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md#security-hardening-required-before-every-release) covers the AGNOS path only.
- [ ] **Tests**: `scripts/test.sh` ≥ 30 assertions covering arg parsing, RTT formatting, summary computation, error paths. `tests/yo.fcyr` fuzz harness for the response-frame parser. `tests/yo.bcyr` benchmark vs Linux's `iputils-ping` on the same hardware (within 10% wall-clock parity, target binary size ≤ 30 KB).
- [ ] **Docs**: ADR for the kernel-syscall-shape decision (focused `icmp_echo` vs general `net_send_raw`), architecture note for the response-frame parsing invariants, guide for the diagnostic flow when 100% loss happens.
- [ ] **CI green**: `.github/workflows/{ci,release}.yml` both green on the v1.0 candidate commit. Release workflow auto-uploads `build/yo` to the GitHub release.

---

## Out of scope (for v1.0)

Deliberate exclusions — keeps future contributors from adding to v1.0 by accident.

- **Privilege model** — yo will require CAP_NET_RAW-equivalent (kavach capability) for ICMP raw send. The capability-gating story is in `aegis` / `kavach`, not in yo itself.
- **Multi-host load-test harness** — that's a `whirl --bench`-class concern, not a ping-class concern.
- **GUI** — TUI / GUI front-end. yo is CLI-only; future graphical network-diagnostic surfaces belong in a separate `nexus`-class repo if anyone wants one.
- **Windows / macOS host targets** — yo targets the AGNOS kernel + the Cyrius cross-platform stdlib. Run it on Linux for now via the same Cyrius cross-platform path other tools use; macOS / Windows ports defer to when the broader Cyrius stdlib gains those targets at parity.

---

## Cross-references

- **Substrate**: [taar (planned)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — extracts when `whirl` or `dig` arrives.
- **Sibling tools**: [whirl (planned)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md), [dig (planned)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md).
- **Iron dependency**: [agnos r8169 RX-path 5-part bundle](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — LAN-on-iron path unblocks when Attempt 97 validates.
- **Kernel-growth posture**: AGNOS `state.md` + memory [[project_agnos_kernel_growth_rules]].
- **Naming lane**: English-wordplay / trickster lane per [[feedback_naming_lanes]] memory. Family: cmdrs, bnrmr, iam, hapi, kii, yo, whirl, dig.
