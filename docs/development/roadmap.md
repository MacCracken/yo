# yo — Roadmap

> **Status**: Active | **Last Updated**: 2026-05-23 (post 0.5.0 IPv6 literal probe)
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
| **0.4.1** | 2026-05-23 | **Reverse DNS.** `yo 8.8.8.8` now banners as `yo 8.8.8.8 (dns.google) — 56 bytes`. `dns_reverse_resolve` issues a PTR query against `D.C.B.A.in-addr.arpa.` with 1 s timeout / 1 attempt. New helpers: `_dns_build_reverse_qname`, `_dns_build_ptr_query`, `_dns_decode_name` (compressed-pointer-aware with 16-jump loop guard), `_dns_parse_ptr_response`. Factored `_dns_walk_to_type` shared by forward+reverse parsers. `-n` / `--numeric` CLI flag suppresses the lookup. 169 unit assertions (+36). |
| **0.4.2** | 2026-05-23 | **Multiple targets.** `yo router 8.8.8.8 1.1.1.1` runs each target sequentially with its own banner + summary block; non-quiet mode separates them with a blank line. Unresolvable hosts no longer abort — error to stderr, continue to next target. Aggregate exit: `0` if any target had any reply, `2` on resolve/socket error with no replies, `1` otherwise. New accessors: `cli_target_count`, `cli_target_at`. 181 unit assertions (+12). |
| **0.4.3** | 2026-05-23 | **TTL display.** Per-packet output now shows the response TTL: `seq=0  ttl=57  rtt=5.83 ms`. `IP_RECVTTL` socket option enabled in `platform_icmp_open`; new `platform_icmp_recv_ext(fd, buf, maxlen, ttl_out)` switches to `recvmsg` (syscall 47) and walks the ancillary cmsg chain via the pure helper `_lx_cmsg_find_ttl`. `output_reply` gains a `ttl` parameter — chunk omitted gracefully when 0. Closes the 0.4.x band; next milestone is 0.5.x IPv6. 187 unit assertions (+6). |
| **0.5.0** | 2026-05-23 | **IPv6 literal probe.** `yo ::1`, `yo 2001:db8::1`, full eight-group form, ULA/loopback all work end-to-end against the Linux AF_INET6 SOCK_DGRAM ICMPv6 path. New `src/ipv6.cyr` parser (RFC 4291, single `::`, case-insensitive, 16 packed bytes network-order). `src/icmp.cyr` adds ICMPV6_ECHO_REQUEST/REPLY + `icmp6_build_echo_request` (kernel fills checksum via `IPV6_CHECKSUM` offset=2). `src/platform_linux.cyr` adds `_lx_sockaddr_in6`, `platform_icmp6_open/_send_to/_recv_ext`, `_lx_cmsg_find_hoplimit`. `probe_run(target, af, addr_arg, ...)` dispatches v4 vs v6 per-target; multi-target invocations can mix families. Deferred to 0.5.1: AAAA lookup, `ip6.arpa` PTR, `-4`/`-6` flags, scope IDs, IPv4-embedded textual form. 252 unit assertions (+65). |

---

## Backlog — path to v1.0

Ordered by dependency. Items further down depend on items earlier.

### 0.4.x — DNS + UX polish (Linux-only feature work)

Everything in this band is achievable on the Linux backend alone — no new platform integration needed.

- [x] **DNS resolution** (`yo google.com`) — landed in 0.4.0. `src/dns.cyr`: `/etc/resolv.conf` parser, UDP query, RFC 1035 response parse with compressed-pointer + CNAME-skip support. Did NOT trigger `taar` extraction per [[feedback-yo-extract-after-second-consumer]] — still waiting on `dig`.
- [x] **Stable banner on hostname target** — landed in 0.4.0. `yo google.com` now produces `yo google.com (142.x.y.z) — 56 bytes` and probes normally; NXDOMAIN exits 2 with `yo: cannot resolve host: <name>`.
- [x] **Reverse DNS lookup** — landed in 0.4.1. PTR query against `D.C.B.A.in-addr.arpa.` with compressed-name decoder; banner shows `yo 8.8.8.8 (dns.google) — 56 bytes` when a PTR exists. `-n` / `--numeric` flag suppresses the lookup.
- [x] **Multiple targets** (`yo router 8.8.8.8`) — landed in 0.4.2. Sequential per-target probe with own banner + summary; aggregate exit code (`0` any-reply / `2` any-error-no-reply / `1` otherwise). Unresolvable hosts log to stderr and don't abort the run.
- [x] **TTL / hop-limit display** — landed in 0.4.3. `IP_RECVTTL` enabled on the socket; `recvmsg`-based `platform_icmp_recv_ext` walks the cmsg chain for `(IPPROTO_IP, IP_TTL)`. Per-packet output renders `seq=N  ttl=T  rtt=X.XX ms`; chunk omitted gracefully when the kernel doesn't surface a TTL cmsg.

### 0.5.x — IPv6

- [x] **IPv6 colon-hex parser** (`::1`, `2001:db8::1`, full 8-group) — landed in 0.5.0. `src/ipv6.cyr`, 16 packed bytes network-order, single `::` per RFC 4291, case-insensitive. Scope IDs and IPv4-embedded textual form deferred.
- [x] **ICMPv6 framing** — landed in 0.5.0. Echo Request = type 128, Reply = 129. Kernel fills the checksum on AF_INET6 SOCK_DGRAM when `IPV6_CHECKSUM` is enabled with offset=2 (no pseudo-header math needed in yo).
- [x] **Platform IPv6 surface** — landed in 0.5.0. `_lx_sockaddr_in6` (28 B), `platform_icmp6_open/_send_to/_recv_ext`, hop-limit cmsg walker. AF_INET6=10, IPPROTO_ICMPV6=58, IPPROTO_IPV6=41.
- [ ] **AAAA DNS lookup + `-4` / `-6` flags** (0.5.1). Hostname targets currently resolve A only; `-4` / `-6` only matters once AAAA is on the table. Also includes `ip6.arpa` PTR reverse-DNS so `yo 2001:4860:4860::8888` banners `(dns.google)`.
- [ ] **Scope IDs + IPv4-embedded form** (0.5.1 or later). `fe80::1%eth0` (zone-index lookup) and `::ffff:1.2.3.4` (dotted-quad embedded in v6).

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
