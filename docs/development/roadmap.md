# yo — Roadmap

> **Status**: Active | **Last Updated**: 2026-05-23 (post 0.4.0 DNS)
>
> Milestone path from scaffold through v1.0 (POSIX-ping feature parity, multi-backend). Per first-party-documentation roadmap shape: **Completed** / **Backlog** / **Future** / **v1.0 criteria**.
>
> Volatile state (binary size, test count, current cycle) lives in [`state.md`](state.md). This file is the milestone plan; state.md is the live snapshot.
>
> **Big shift**: 2026-05-23 pivot from "agnos-only, blocked on kernel surface" to **multi-backend, Linux first**. AGNOS, Windows, Apple backends slot in later. See [[project-yo-multi-backend-pivot]].

---

## Completed

| Version | Landed | Items |
|---|---|---|
| **0.1.0** | 2026-05-23 | Initial `cyrius init` scaffold. README + CLAUDE.md + LICENSE + CHANGELOG + cyrius.cyml + tests/yo.{tcyr,bcyr,fcyr} + `.github/workflows/{ci,release}.yml`. Stub `main.cyr` prints `hello from yo`. Stdlib vendored in `lib/`. |
| **0.3.0** | 2026-05-23 | **Linux MVP.** Full CLI (`-c -W -i -s -q -v -h` + long forms) via `lib/flags.cyr`. Strict IPv4 dotted-quad parser. RFC 792 ICMP framing + RFC 1071 checksum. RTT accumulator + README-shaped per-packet/summary output. Linux backend via `src/platform_linux.cyr` (unprivileged SOCK_DGRAM ICMP, falls back to SOCK_RAW). Probe loop with SO_RCVTIMEO. Ctrl-C handling via signalfd. POSIX exit codes (0 / 1 / 2). 87 unit assertions. `workflow_call:` enabled in `ci.yml` so `release.yml` can gate on it. |
| **0.4.0** | 2026-05-23 | **DNS resolution.** `yo <hostname>` works end-to-end. `src/dns.cyr` — RFC 1035 A-record resolver: QNAME encoder, query builder, response parser (compressed-pointer NAMEs, skips CNAMEs to first A record), `/etc/resolv.conf` line parser, fallback to `1.1.1.1`. UDP primitives + `platform_read_file` added to `platform_linux.cyr`. Banner shows `yo google.com (142.x.y.z)` when DNS was used. NXDOMAIN exits 2 with `yo: cannot resolve host: <name>`. 133 unit assertions (+46). |

---

## Backlog — path to v1.0

Ordered by dependency. Items further down depend on items earlier.

### 0.4.x — DNS + UX polish (Linux-only feature work)

Everything in this band is achievable on the Linux backend alone — no new platform integration needed.

- [x] **DNS resolution** (`yo google.com`) — landed in 0.4.0. `src/dns.cyr`: `/etc/resolv.conf` parser, UDP query, RFC 1035 response parse with compressed-pointer + CNAME-skip support. Did NOT trigger `taar` extraction per [[feedback-yo-extract-after-second-consumer]] — still waiting on `dig`.
- [x] **Stable banner on hostname target** — landed in 0.4.0. `yo google.com` now produces `yo google.com (142.x.y.z) — 56 bytes` and probes normally; NXDOMAIN exits 2 with `yo: cannot resolve host: <name>`.
- [ ] **Reverse DNS lookup**. Banner shows `yo 142.250.x.x (lga25s71-in-f14.1e100.net)` when target was an IP. Forward-DNS direction already done in 0.4.0. Implementation: PTR query against `D.C.B.A.in-addr.arpa.`, reuse `_dns_build_query`/`_dns_parse_response` core with a tiny extra path for parsing a name out of an answer's RDATA (currently we only parse A-record RDATA).
- [ ] **Multiple targets** (`yo router 8.8.8.8`). Sequential probe runs with per-target summary, then a combined exit code.
- [ ] **TTL / hop-limit display** in per-packet output (read from response IP header on SOCK_RAW; from cmsg on SOCK_DGRAM via `IP_RECVTTL`).

### 0.5.x — IPv6

- [ ] IPv6 dotted-colon parser (`::1`, `fe80::...`). Inline in `src/ipv6.cyr` mirroring `ipv4.cyr` shape.
- [ ] ICMPv6 framing in `src/icmp.cyr` (or `src/icmp6.cyr` if it grows large). Echo Request = type 128, Echo Reply = type 129; checksum includes IPv6 pseudo-header.
- [ ] `platform_linux.cyr` adds `AF_INET6` socket open, `sockaddr_in6` (28 bytes) builder, IPPROTO_ICMPV6 = 58.
- [ ] CLI gains `-4` / `-6` to force address family when the target is a hostname.

### 0.6.x — AGNOS backend

**Trigger**: agnos lands the kernel ICMP surface. Blocked on agnos r8169 RX-path 5-part bundle iron-validating (Attempt 97 pending; see [agnosticos iron-nuc-zen-log](https://github.com/MacCracken/agnosticos/blob/main/docs/development/iron-nuc-zen-log.md)).

- [ ] Cyrius-native syscall surface in `agnos/kernel/core/net.cyr`. Per [[project_agnos_kernel_growth_rules]] — NOT POSIX `socket()`. Shape: either focused `icmp_echo(addr, timeout_ms) → rtt_us` or general `net_send_raw` + `net_recv_raw` pair. The Linux backend in `src/platform_linux.cyr` is the concrete reference for what shape yo needs; kernel can match it 1:1 or offer the focused form (in which case `platform_agnos.cyr` collapses the abstraction).
- [ ] Per-process ICMP listener registration in agnos kernel (analogous to UDP listener table at `net.cyr:142-196`).
- [ ] QEMU smoke: `qemu-net-icmp-smoke.sh` boots kernel + sends a self-loopback ICMP echo, asserts rtt > 0.
- [ ] `src/platform_agnos.cyr` in yo, dispatched by `#ifdef CYRIUS_TARGET_AGNOS` in `src/platform.cyr` (the `_LX_*` constants in `platform_linux.cyr` get a sibling `_AG_*` namespace).
- [ ] `yo`'s `src/icmp.cyr` checksum logic is reused byte-for-byte by the agnos kernel verification path.

### 0.7.x — Iron validation (AGNOS backend)

**Trigger**: 0.6.x AGNOS backend lands.

- [ ] First iron run: `yo 192.168.1.1` on archaemenid (AGNOS-booted). Expected: RTT ≤ 1 ms against the home gateway.
- [ ] First WAN run from AGNOS: `yo 8.8.8.8`. Expected: 5-30 ms from a US residential connection.
- [ ] First-fail diagnostics: when 100% loss, dump kernel ICMP send/recv counters via a `--diag` flag (matches `read-boot-log.sh` pattern for r8169 CMOS slots).

### 0.8.x — `taar` substrate extraction

**Trigger**: a second consumer (likely `dig`) has working network code that needs the same primitives yo has built inline.

Per [[feedback-yo-extract-after-second-consumer]]: don't pre-build the shared lib from naming alone. The current state (`dig` is scaffold-only) is NOT the trigger; the trigger is dig having a real DNS resolver that wants to share the UDP/socket plumbing yo built.

- [ ] Open `~/Repos/taar` from yo's `src/platform_linux.cyr` + `src/dns.cyr` + dig's resolver core. Reshape only after both consumers push back on the abstraction.
- [ ] Add `taar = { path = "../taar" }` to `yo/cyrius.cyml [deps]` and `dig/cyrius.cyml [deps]`.
- [ ] Bump yo to consume `taar` without CLI surface change. The extraction is internal.

---

## Future (post-1.0)

Lower priority. Item shape pinned for orientation; specific versions TBD.

- [ ] **Flood mode** (`yo -f`) — POSIX `ping -f` equivalent. Send packets as fast as the host can. Stress-tests the kernel network stack.
- [ ] **Timestamp option** (`yo -D`) — RFC-style timestamps per packet, for log-aggregator piping.
- [ ] **Bind-source-address** (`yo -I <iface_or_ip>`) — choose source interface. Useful when a host has multiple active links.
- [ ] **Path-MTU discovery probe** (`yo -M do`) — set DF flag, walk MTU range. Diagnoses tunnel / VPN MTU issues.
- [ ] **JSON output** (`yo --json`) — machine-readable summary for piping into other tools (`sutra`, `aegis`, `phylax` audit chains).
- [ ] **Audit-chain integration** — when `libro` lands, log every `yo` invocation + result to the audit chain. Forensic value: *"who pinged what, when, with what outcome."*
- [ ] **Windows backend** (`src/platform_windows.cyr`). Likely via `IcmpSendEcho` from `Iphlpapi.dll` once Cyrius gains Windows targets at parity.
- [ ] **Apple backend** (`src/platform_apple.cyr`). macOS supports unprivileged ICMP DGRAM the same way Linux does; iOS / sandboxed environments TBD.

---

## v1.0 criteria (release gate)

Ship 1.0 when all of these are true. Pre-1.0 minor cycles can land partial subsets; the v1.0 tag is the all-of-these gate.

- [ ] **Feature parity with POSIX `ping`** on the Linux backend: `-c`, `-W`, `-i`, `-s`, `-q`, `-v`, IPv4 + IPv6, DNS resolution, reverse-DNS display, multiple targets, TTL display. (Flood `-f`, timestamp `-D`, bind `-I`, MTU `-M` deferred to post-1.0.)
- [ ] **AGNOS backend working** end-to-end. `src/platform_agnos.cyr` lands ICMP via the sovereign kernel surface. QEMU smoke + iron validation both green.
- [ ] **LAN-on-iron validated** on archaemenid against the home gateway (`192.168.1.1`) and at least one WAN host (`8.8.8.8`), AGNOS-booted.
- [ ] **No POSIX `socket()` in the AGNOS backend** (`src/platform_agnos.cyr`). Sovereign kernel primitives only on that path. Linux backend keeps using POSIX socket() pragmatically per the per-backend sovereignty rule. Audit pass per [first-party-standards § Security Hardening](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md#security-hardening-required-before-every-release) covers the AGNOS path only.
- [ ] **Tests**: ≥ 100 assertions in `tests/yo.tcyr` covering arg parsing, framing, checksum, IPv4 + IPv6 parsing, RTT format, summary computation, error paths. `tests/yo.fcyr` fuzz harness for the response-frame parser. `tests/yo.bcyr` benchmark vs Linux's `iputils-ping` (within 10% wall-clock parity, target binary size ≤ 30 KB after DCE).
- [ ] **Substrate extraction decision made**: either `taar` lands (with `dig` as the second consumer) OR an ADR explicitly defers it. Don't ship 1.0 with the substrate question unanswered.
- [ ] **Docs**: ADR for the per-backend sovereignty rule, ADR for the kernel-syscall-shape decision (focused vs general), architecture note for the response-frame parsing invariants, guide for the diagnostic flow when 100% loss happens.
- [ ] **CI green**: `.github/workflows/{ci,release}.yml` both green on the v1.0 candidate commit. `workflow_call:` reusable invocation pattern in place. Release workflow auto-uploads `build/yo` to the GitHub release.

---

## Out of scope (for v1.0)

Deliberate exclusions — keeps future contributors from adding to v1.0 by accident.

- **Privilege model** — yo on the AGNOS backend will require a `kavach` capability for raw send; on Linux it works via `ping_group_range` (unprivileged) or CAP_NET_RAW (root). The capability-gating story is in `aegis` / `kavach`, not in yo itself.
- **Multi-host load-test harness** — that's a `whirl --bench`-class concern, not a ping-class concern.
- **GUI** — TUI / GUI front-end. yo is CLI-only; future graphical network-diagnostic surfaces belong in a separate `nexus`-class repo if anyone wants one.
- **Windows / macOS backends pre-1.0** — those are post-1.0 work even though the platform layer is structured to accept them.
- **`taar` extraction pre-emptively** — wait for the second-consumer signal (dig with real code). Naming a future shared lib is not the same as building it.

---

## Cross-references

- **Pivot memory**: [[project-yo-multi-backend-pivot]] — the 2026-05-23 multi-backend pivot and its rationale.
- **Extraction memory**: [[feedback-yo-extract-after-second-consumer]] — don't pre-build shared libs from naming alone.
- **Substrate (planned)**: [taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — extracts when dig has working code.
- **Sibling tools**: [whirl (planned)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md), [dig (scaffold only)](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md).
- **Iron dependency** (AGNOS backend only): [agnos r8169 RX-path 5-part bundle](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — AGNOS backend unblocks when Attempt 97 validates.
- **Kernel-growth posture**: AGNOS `state.md` + memory [[project_agnos_kernel_growth_rules]].
- **Naming lane**: English-wordplay / trickster lane per [[feedback_naming_lanes]] memory. Family: cmdrs, bnrmr, iam, hapi, kii, yo, whirl, dig.
