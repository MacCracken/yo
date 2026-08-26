# yo — Roadmap

> **Status**: Active | **Last Updated**: 2026-08-26 (post 0.5.11 — **§ 0.6.x and § 0.7.x closed**; the AGNOS backend ships, is iron-validated, and now has an automated QEMU gate)
>
> Milestone path from scaffold through v1.0 (POSIX-ping feature parity, multi-backend). Per first-party-documentation roadmap shape: **Completed** / **Backlog** / **Future** / **v1.0 criteria**.
>
> Volatile state (binary size, test count, current cycle) lives in [`state.md`](state.md). This file is the milestone plan; state.md is the live snapshot.
>
> **Big shift**: 2026-05-23 pivot from "agnos-only, blocked on kernel surface" to **multi-backend, Linux first**. See [[project-yo-multi-backend-pivot]]. The pivot has since played out in full — the AGNOS backend landed at 0.5.3 and is validated on iron and in QEMU; Windows and Apple remain post-1.0.

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
| **0.5.1** | 2026-05-23 | **IPv6 polish.** AAAA DNS lookup (`dns_resolve_aaaa`, query type 28), `ip6.arpa` PTR reverse-DNS (32 single-nibble labels least-sig-first), `-4` / `-6` family-forcing flags with mutual-exclusion check (`CLI_ERR_AF_CONFLICT`), RFC 5952 canonical v6 banner formatter (`output_ipv6_to_buf` — longest zero-run compressed to `::`, no leading zeros, lowercase). `yo dns.google` defaults to A; `yo -6 dns.google` does AAAA. `yo ::1` banners `(localhost)` via ip6.arpa. Deferred to 0.5.2 or later: scope IDs (`%iface`), IPv4-embedded textual form (`::ffff:1.2.3.4`). 298 unit assertions (+46). |
| **0.5.2** | 2026-05-23 | **Scope IDs + IPv4-embedded textual form** (closes 0.5.x band). `ipv6_parse_ex` splits the `%zone` suffix; `platform_resolve_ifindex` reads `/sys/class/net/<iface>/ifindex` and the resolved id is written to `sin6_scope_id` (off 24 of sockaddr_in6). `_ipv6_parse_with_v4` accepts the dotted-quad tail (`::ffff:1.2.3.4`, `2001:db8::1.2.3.4`, full no-`::` form) via pre-scan + `<prefix>0:0` synthesis + last-4-byte overwrite. RFC 5952 §5 v4-mapped output formatter. v4-mapped destinations dispatch via the IPv4 socket (ICMPv6 can't carry an ICMPv4 probe). `yo: unknown interface: <name>` exit 2 on bad zone. 365 unit assertions (+67). |
| **0.5.3** | 2026-06-14 | **AGNOS breakout — yo builds for the sovereign kernel.** `src/platform_agnos.cyr`: the POSIX `socket()` path replaced by ring-3 agnos syscalls. **The ICMP model bridge** — `icmp_echo`(#55) is one-shot (send + wait + RTT in one blocking call), so yo's `open → send_to → recv_ext` surface collapses onto it: `send_to` stores the request, `recv_ext` calls `icmp_echo` then synthesises the reply from the stored request (type 8→0, checksum recomputed via yo's own `icmp_checksum`). DNS rides `udp_bind/send/recv/unbind` (#51-54). `src/platform.cyr` dispatches on `#ifdef CYRIUS_TARGET_AGNOS`. Pin 6.0.51 → 6.2.5. |
| **0.5.4** | 2026-06-14 | Pin → 6.2.6; dropped the `syscall(40)/(41)` chrono workaround for the `sys_uptime_ms` / `sys_sleep_ms` wrappers. |
| **0.5.5** | 2026-06-15 | **`taar` fold — the IPv4 codec extracted.** `src/ipv4.cyr` removed; `ipv4_parse` now comes from the shared substrate. This is § 0.8.x, landed early because `dig` became the real second consumer. |
| **0.5.6** | 2026-06-19 | Pin → 6.2.24; taar → 0.3.0. |
| **0.5.7** | 2026-06-23 | **AGNOS nameserver prefers the kernel-leased resolver** — `net_config`#61 field 3 via `platform_dns_server`, ahead of `/etc/resolv.conf` and the `1.1.1.1` fallback. Fixes the off-subnet routing gap that froze `yo google.com` on iron. taar → 0.3.1. |
| **0.5.8** | 2026-08-26 | Pin 6.2.24 → **6.5.35** (three minor bands); taar → **0.5.0**. Verified source-clean up front by diffing cyrius's `api-surface.snapshot`: the stdlib surface yo uses grew 219 → 280 symbols with **zero** removals or arity changes. No source edits. |
| **0.5.9** | 2026-08-26 | **Test-gate soundness.** `assert_summary()` returns the raw failure COUNT and a wait status is 8 bits, so exactly 256/512/768 failures exited 0 and scored PASS. All three entry points now clamp to 1, and every hardcoded exit syscall moved to `sys_exit_group` (portable across x86_64 / aarch64 / agnos). |
| **0.5.10** | 2026-08-26 | Retired the last raw syscall number in the AGNOS backend — `syscall(61, 3)` → `sys_net_dns_server()`. (#61 is `net_config` on AGNOS but `wait4(2)` on Linux.) |
| **0.5.11** | 2026-08-26 | **`--diag` first-fail diagnostics + the AGNOS run gate.** `--diag` dumps per-backend state on 100% loss (Linux: socket flavour, `ping_group_range`, `sendto`/`recv` errno; AGNOS: the `net_config` lease + the `icmp_echo` return). `scripts/agnos-qemu-smoke.sh` boots agnos in QEMU, types a probe at the shell over QMP `send-key`, and asserts on serial — **2/2 replies, 0% loss** against the SLIRP gateway, and correctly **FAILs** against an unreachable one. Closes § 0.6.x and § 0.7.x. |

---

## Backlog — path to v1.0

Ordered by dependency. Items further down depend on items earlier.

### DNS + UX polish *(0.4.x)* — **CLOSED**

Everything in this band is achievable on the Linux backend alone — no new platform integration needed.

- [x] **DNS resolution** (`yo google.com`) — landed in 0.4.0. `src/dns.cyr`: `/etc/resolv.conf` parser, UDP query, RFC 1035 response parse with compressed-pointer + CNAME-skip support. Did NOT trigger `taar` extraction per [[feedback-yo-extract-after-second-consumer]] — still waiting on `dig`.
- [x] **Stable banner on hostname target** — landed in 0.4.0. `yo google.com` now produces `yo google.com (142.x.y.z) — 56 bytes` and probes normally; NXDOMAIN exits 2 with `yo: cannot resolve host: <name>`.
- [x] **Reverse DNS lookup** — landed in 0.4.1. PTR query against `D.C.B.A.in-addr.arpa.` with compressed-name decoder; banner shows `yo 8.8.8.8 (dns.google) — 56 bytes` when a PTR exists. `-n` / `--numeric` flag suppresses the lookup.
- [x] **Multiple targets** (`yo router 8.8.8.8`) — landed in 0.4.2. Sequential per-target probe with own banner + summary; aggregate exit code (`0` any-reply / `2` any-error-no-reply / `1` otherwise). Unresolvable hosts log to stderr and don't abort the run.
- [x] **TTL / hop-limit display** — landed in 0.4.3. `IP_RECVTTL` enabled on the socket; `recvmsg`-based `platform_icmp_recv_ext` walks the cmsg chain for `(IPPROTO_IP, IP_TTL)`. Per-packet output renders `seq=N  ttl=T  rtt=X.XX ms`; chunk omitted gracefully when the kernel doesn't surface a TTL cmsg.

### IPv6 *(0.5.x)* — **CLOSED**

- [x] **IPv6 colon-hex parser** (`::1`, `2001:db8::1`, full 8-group) — landed in 0.5.0. `src/ipv6.cyr`, 16 packed bytes network-order, single `::` per RFC 4291, case-insensitive. Scope IDs and IPv4-embedded textual form deferred.
- [x] **ICMPv6 framing** — landed in 0.5.0. Echo Request = type 128, Reply = 129. Kernel fills the checksum on AF_INET6 SOCK_DGRAM when `IPV6_CHECKSUM` is enabled with offset=2 (no pseudo-header math needed in yo).
- [x] **Platform IPv6 surface** — landed in 0.5.0. `_lx_sockaddr_in6` (28 B), `platform_icmp6_open/_send_to/_recv_ext`, hop-limit cmsg walker. AF_INET6=10, IPPROTO_ICMPV6=58, IPPROTO_IPV6=41.
- [x] **AAAA DNS lookup + `-4` / `-6` flags** — landed in 0.5.1. `dns_resolve_aaaa` issues type-28 queries; `-4` / `-6` restrict resolution to one family with `CLI_ERR_AF_CONFLICT` on both. `ip6.arpa` PTR reverse-DNS also in 0.5.1; RFC 5952 canonical formatter for AAAA-resolved banners.
- [x] **Scope IDs + IPv4-embedded form** — landed in 0.5.2. `ipv6_parse_ex` splits `%zone`; `platform_resolve_ifindex` (Linux: `/sys/class/net/<iface>/ifindex`) maps to sin6_scope_id. `_ipv6_parse_with_v4` accepts `::ffff:1.2.3.4`, `2001:db8::1.2.3.4`, and the full no-`::` form. v4-mapped addresses dispatch through the IPv4 socket because ICMPv6 can't carry an ICMPv4 probe. RFC 5952 §5 v4-mapped output. **0.5.x band closed.**

### AGNOS backend *(planned as 0.6.x — actually landed 0.5.3 … 0.5.11)* — **CLOSED**

**Both gates are closed, and both were closed for a while before this file noticed.**
Verified against live source 2026-08-26, not against sibling-repo prose:

1. ~~`cyrius/lib/args.cyr` agnos branch~~ — **closed at cyrius 6.0.87 / 6.1.32.**
   `lib/args.cyr:99` dispatches `#ifdef CYRIUS_TARGET_AGNOS` → `lib/args_agnos.cyr`,
   which recovers argc/argv from the SysV init stack the kernel builds at exec (cycc
   emits `mov r15, rsp` as the first runtime instruction on that target and reserves
   r15 from regalloc).
2. ~~Ring-3 ICMP/UDP/ifindex syscalls in agnos~~ — **closed at agnos 1.45.4.**
   `icmp_echo`(#55) returns RTT in ms or -1; UDP is #51-54; `net_config` is #61.
   cyrius ships typed wrappers for all of them.

- [x] Promote `icmp_ping` to a ring-3 syscall — agnos 1.45.4, as `icmp_echo`#55. The
      kernel kept the **focused** shape, so `platform_agnos.cyr` collapses
      `_send_to + _recv` onto it. See [ADR 0002](../adr/0002-focused-kernel-icmp-syscall.md).
- [x] `cyrius/lib/args.cyr` agnos branch — cyrius 6.0.87 / 6.1.32.
- [x] `src/platform_agnos.cyr`, dispatched by `#ifdef CYRIUS_TARGET_AGNOS` in
      `src/platform.cyr` — landed 0.5.3.
- [x] QEMU smoke — `scripts/agnos-qemu-smoke.sh` (0.5.11). Boots agnos against an ext2
      rootfs carrying `/bin/agnsh` + `/bin/yo` and types a probe over QMP `send-key`
      (agnos has no serial RX; console input is a USB-keyboard read). **2/2 replies,
      0% loss** against the SLIRP gateway; correctly **FAILs** against an
      unreachable address. (Such a run also prints `ttl=64`, but that is a literal
      written by `_ag_icmp_pong` — `icmp_echo`#55 surfaces no reply TTL — so it is
      not evidence of anything. See [ADR 0002](../adr/0002-focused-kernel-icmp-syscall.md) § 4.)
- [x] `src/icmp.cyr`'s checksum is shared byte-for-byte with the kernel path — it is
      modelled on `agnos/kernel/core/net.cyr`, and `_ag_icmp_pong` recomputes the
      synthesised reply's checksum with yo's own `icmp_checksum`.
- [ ] ~~Per-process ICMP listener registration in the agnos kernel~~ — **obsolete.**
      It presupposed a general send/recv surface. `icmp_echo`#55 is one-shot and
      matches replies inside the kernel, so there is no per-process listener to
      register. Kept visible rather than deleted because it was a planned item.

### Iron validation *(planned as 0.7.x — landed via agnos burns 1.45.16 / 1.51.7)* — **CLOSED**

Validated on archaemenid, recorded in **agnos's** CHANGELOG (yo's own docs missed it
for four releases):

- [x] First iron run + first WAN run — agnos **1.45.16** burn (2026-06-23):
      `yo google.com` → **2/4, 50% loss**. Root cause was not yo: the RX ring was
      serviced only while a ring-3 tool sat in its own `net_poll()` loop, so LAN
      chatter overran the 64-deep ring between commands. Fixed in agnos 1.45.17 by
      draining RX every 100 Hz tick. Invisible in QEMU, because SLIRP is
      point-to-point — the burn was the only way to see it.
- [x] Clean iron run — agnos **1.51.7** burn (2026-07-02): `yo google.com` **4/4 at
      0% loss**, three RTTs at sub-tick `0.00 ms`, real DHCP lease `192.168.1.195`,
      `net: L2 OK`, no storm, no hang.
- [x] First-fail diagnostics — `--diag`, landed 0.5.11. **Note the roadmap asked for
      "kernel ICMP send/recv counters" and those do not exist**: the agnos kernel keeps
      no ICMP tx/rx counters and exposes none to ring 3 (`net_config` has exactly four
      fields and returns -1 for anything else). `--diag` dumps the configuration state
      that IS reachable — the DHCP lease — plus the raw `icmp_echo` return. Counters
      remain an agnos-side ask, not a yo one.

### `taar` substrate extraction *(planned as 0.8.x — landed early at 0.5.5)* — **CLOSED**

The trigger fired ahead of schedule: `dig` grew a real DNS resolver and became the
genuine second consumer, exactly as [[feedback-yo-extract-after-second-consumer]]
required. The extraction was not pre-built from naming.

- [x] Open `~/Repos/taar` — done; yo folded `src/ipv4.cyr` onto it at 0.5.5.
- [x] `[deps.taar]` in yo's manifest — `path = "../taar"` for local dev, `git`+`tag`
      published fallback. Currently **taar 0.5.0**.
- [x] Consume `taar` with no CLI surface change — the extraction was internal. yo uses
      exactly one taar symbol, `ipv4_parse`; the bundle's `socket`/`dns` modules ride
      along and DCE out.

> **Every band above is closed.** The bands were named for the version they were
> expected to land in; three of them landed early, which is why their labels no
> longer match their release. The open work is § 0.6.x below plus § v1.0 criteria.

### 0.6.x — deferred-work cleanup *(open — this is the current band)*

Collected by a deferred-language sweep of `src/`, `tests/`, `scripts/`, `docs/` and
the workflow YAML at 0.6.0. Everything here was previously a comment, an aside, or a
line of prose promising future work; nothing was tracked. Split by who can act.

**yo-owned — actionable in this repo:**

- [x] **Every raw `write` routed through the stdlib** — done in 0.6.0. The
      `[cleanup: route this through the stdlib.]` marker had sat in
      `src/platform_agnos.cyr` since 0.5.3: the AGNOS arm defined a Linux-named
      `_LX_SYS_WRITE = 1` purely so `probe.cyr`'s error path would resolve there.
      Fixing it properly meant fixing all of them — `_puts`, `_eputs`, `_emit_lf`,
      `cli_print_usage`, `_output_puts` and the two single-byte writes were all
      `syscall(1, ...)`, which hardcodes the **x86_64** write number (it is 64 on
      aarch64). All now call `sys_write`, which is arch-dispatched, and both
      `_LX_SYS_WRITE` constants are deleted. Output verified byte-identical.
- [ ] **IPv6 nameservers in `/etc/resolv.conf` are ignored** (`src/dns.cyr:249`). The
      parser reads `nameserver <addr>` lines and passes the value to `ipv4_parse`, so a
      `nameserver fe80::1` or any v6 resolver is silently skipped. On a v6-only network
      yo falls through to the `1.1.1.1` fallback and DNS appears to work by accident.
      Needs `ipv6_parse` on that path plus a v6 UDP query socket.
- [x] **`README.md` reconciled** — done in 0.6.0. It documented `scripts/install.sh`,
      which does not exist; described the AGNOS backend as "planned"; promised
      `net_send_raw` primitives that [ADR 0002](../adr/0002-focused-kernel-icmp-syscall.md)
      rejected; said `taar` "extracts when the second consumer arrives" (it did, at
      0.5.5); and showed example output with the wrong payload size and no TTL.
- [ ] **`--aarch64` builds clean and would be wrong.** `src/platform_linux.cyr:22-34`
      hardcodes x86_64 syscall numbers; the aarch64 stdlib peer has no `SYS_SENDTO`, so
      `44` would arrive as `fstatfs(2)`. Latent — yo ships x86_64 only — but it blocks
      any future aarch64 target and a green build must not be read as support. Fix is
      to route through the arch-dispatched `sys_*` wrappers and add a CI leg that
      *runs* the binary under `qemu-aarch64`. taar hit this exact defect at its 0.3.3.
      **Partially reduced in 0.6.0**: every raw `write` now goes through `sys_write`,
      so the output path is arch-clean. What remains is the socket surface —
      `_LX_SYS_SOCKET`, `_LX_SYS_SENDTO`, `_LX_SYS_RECVFROM`, `_LX_SYS_RECVMSG`,
      `_LX_SYS_SETSOCKOPT`, `_LX_SYS_OPEN`, `_LX_SYS_CLOSE`, `_LX_SYS_READ`,
      `_LX_SYS_NANOSLEEP`, `_LX_SYS_CLOCK_GETTIME`, `_LX_SYS_SIGNALFD4`,
      `_LX_SYS_RT_SIGPROCMASK`.
- [ ] **Decide the binary-size criterion** — see § v1.0 criteria. Either file the
      section-GC ask against cyrius or restate the gate. Do not let it lapse silently.

**Blocked on agnos — kernel asks, not yo work:**

| Ask | Unblocks | Where yo stubs it |
|---|---|---|
| An ICMPv6 syscall | `yo -6` on AGNOS | `platform_icmp6_*` return `-1` (`platform_agnos.cyr:158-160`) |
| An interface-index lookup | `%zone` scope IDs on AGNOS | `platform_resolve_ifindex` returns 0 (`:163`) |
| Ring-3 signal/interrupt infra | Ctrl-C interruption on AGNOS | watch reports unavailable (`:167-168`) |
| `icmp_echo(dst_ip, timeout_ms)` | `-W` on AGNOS (the ~3 s bound is fixed in-kernel) | `_ag_timeout_ms` is read only by the UDP path |
| ICMP tx/rx counters | the counters roadmap § 0.7.x asked `--diag` for | `--diag` dumps the DHCP lease instead |
| Reply-match on identifier **and sequence** | removes an untested concurrency hazard — the kernel matches on identifier only (`net_icmp.cyr:48`), so one ping is in flight kernel-wide | nothing; yo never exercises it (see [ADR 0002](../adr/0002-focused-kernel-icmp-syscall.md)) |

**Blocked on cyrius:**

- [ ] **Section GC / real dead-code stripping.** `CYRIUS_DCE=1` NOPs unreachable
      functions; it does not remove them, so the binary is byte-identical either way.

**Family hygiene:**

- [ ] **`dig` and `whirl` trail yo's toolchain.** yo is on cyrius 6.5.35 / taar 0.5.0;
      `dig` is on 6.2.24 / taar 0.3.1 and `whirl` on 6.4.25 / taar 0.3.1. yo's 0.5.8
      migration evidence (zero stdlib removals across the three-band jump) applies to
      both; `whirl` carries the larger risk since it pulls the crypto/TLS leaves.

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

Ship 1.0 when all of these are true. Status re-assessed 2026-08-26 at 0.6.0 against
the code and against measurements, not against this file's own prior claims.

- [x] **Feature parity with POSIX `ping`** on the Linux backend: `-c`, `-W`, `-i`,
      `-s`, `-q`, `-v`, IPv4 + IPv6, DNS resolution, reverse-DNS display, multiple
      targets, TTL display. Plus `-n`, `-4`/`-6` and `--diag`, which POSIX ping has no
      equivalent of. (Flood `-f`, timestamp `-D`, bind `-I`, MTU `-M` remain post-1.0.)
- [x] **AGNOS backend working** end-to-end. `src/platform_agnos.cyr` reaches ICMP
      through the sovereign kernel surface. QEMU smoke green
      (`scripts/agnos-qemu-smoke.sh`) and iron validation green (agnos 1.51.7 burn).
- [x] **LAN-on-iron validated** on archaemenid, AGNOS-booted — `yo google.com` 4/4 at
      0% loss on the 1.51.7 burn, over a real DHCP lease. **Caveat kept deliberately:
      that burn probed a WAN host by name; a `yo 192.168.1.1` gateway-literal run is
      not separately recorded.** Not re-opening the band for it, but it is the one
      line of the original criterion without its own evidence.
- [x] **No POSIX `socket()` in the AGNOS backend.** `src/platform_agnos.cyr` contains
      no socket call and, since 0.5.10, no raw syscall numbers either — everything
      goes through named cyrius wrappers. Formalised in
      [ADR 0001](../adr/0001-per-backend-sovereignty.md).
- [x] **Tests**: ≥ 100 assertions — **373** in `tests/yo.tcyr`, covering arg parsing,
      framing, checksum, IPv4 + IPv6 parsing, RTT format, summary computation and
      error paths. `tests/yo.fcyr` and `tests/yo.bcyr` both build and run green. The
      gate itself is sound as of 0.5.9 (exit codes clamped).
- [x] **Substrate extraction decision made** — `taar` landed at 0.5.5 with `dig` as
      the genuine second consumer. No ADR deferral needed; the question is answered.
- [ ] **Docs**: ADR for per-backend sovereignty ✅ (0001), ADR for the kernel-syscall
      shape ✅ (0002), architecture note on reply-acceptance invariants ✅ (001), guide
      for the 100%-loss diagnostic flow ✅. *Remaining*: a `README.md` pass, since it
      predates the AGNOS backend shipping.
- [x] **CI green on the v1.0 candidate.** `ci.yml` / `release.yml` both green, and as
      of 0.6.0 CI also runs **`cyrius build --agnos`**, `cyrius bench` and
      `cyrius fuzz`. The `--agnos` step closed the real gap: `src/platform.cyr`
      dispatches on `#ifdef`, so the host build never compiles
      `src/platform_agnos.cyr` and `cyrius test` cannot reach it either — a break in
      the AGNOS arm used to land green. *Still manual:*
      `scripts/agnos-qemu-smoke.sh`, which needs sibling checkouts + QEMU + OVMF a
      GitHub runner does not have. It is deliberately not wired in, because it would
      SKIP on every run and read as coverage that does not exist.

### Two criteria that were re-based (they were unmeasured guesses)

The original gate read *"benchmark vs Linux's `iputils-ping` (within 10% wall-clock
parity, target binary size ≤ 30 KB after DCE)"*. Both halves were written before
anything was measured. Measured on archaemenid 2026-08-26:

| | yo 0.6.0 | iputils `ping` 20250605 | verdict |
|---|---|---|---|
| wall clock, `-c 1 -n 127.0.0.1`, best of 3 × 100 | **381 µs/run** | 458 µs/run | yo ~17% **faster** — passes, and by more than parity |
| binary on disk | **152,704 B** | 155,160 B | yo slightly smaller |

- [x] **Wall-clock parity** — met, and exceeded.
- [ ] **Binary size ≤ 30 KB after DCE — WITHDRAWN AS WRITTEN, needs a new number.**
      The premise is false: `CYRIUS_DCE=1` **NOPs** unreachable functions, it does not
      strip them. The file is byte-for-byte the same size with and without it
      (152,704 B either way; 400 unreachable fns / 68,740 bytes NOPed). So "≤ 30 KB
      after DCE" is not a target yo can hit by any flag it controls — it is a request
      for a linker/GC pass cyrius does not have. Roughly 144 KB of the binary is
      `.text`, most of it the vendored stdlib plus taar's 979-line bundle riding along
      unreferenced. **Decide before 1.0**: either file the section-GC ask against
      cyrius, or re-state the criterion as "no larger than the system `ping`" — which
      yo already satisfies. Do not silently drop it.

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
- **Substrate**: [taar](https://github.com/MacCracken/taar) — **shipped**, currently 0.5.0. yo folded onto it at 0.5.5 and consumes one symbol, `ipv4_parse`.
- **Sibling tools**: `whirl` (curl/wget, 0.6.4) and `dig` (DNS, 0.3.5) — both **real and shipping**, not planned. All three share taar. Family drift as of 2026-08-26: yo is on cyrius 6.5.35 / taar 0.5.0 while dig is on 6.2.24 / taar 0.3.1 and whirl on 6.4.25 / taar 0.3.1.
- **AGNOS backend gates** — **BOTH CLOSED**, verified against live source 2026-08-26: `cyrius/lib/args.cyr:99` has its agnos branch (since cyrius 6.0.87/6.1.32), and `icmp_echo`#55 / UDP #51-54 / `net_config`#61 are ring-3 in `agnos/kernel/core/syscall.cyr` (since agnos 1.45.4). Iron RX was proven long before either. See § 0.6.x.
- **Kernel-growth posture**: agnos kernel *source* (`net_icmp.cyr`, `syscall.cyr`) + memory [[project_agnos_kernel_growth_rules]]. Do NOT trust agnos's state.md for yo's blocker status — it lagged reality (claimed the userland target was missing when it ships in cyrius today).
- **Naming lane**: English-wordplay / trickster lane per [[feedback_naming_lanes]] memory. Family: cmdrs, bnrmr, iam, hapi, kii, yo, whirl, dig.
