# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.5.2] — 2026-05-23

IPv6 tail items from 0.5.1. Scope IDs (`fe80::1%eth0`) for link-local probing and the IPv4-embedded textual form (`::ffff:1.2.3.4`, `2001:db8::1.2.3.4`, `0:0:0:0:0:ffff:1.2.3.4`) for the parser and the RFC 5952 §5 output formatter. v4-mapped destinations dispatch through the IPv4 socket path because ICMPv6 can't carry a v4 probe.

### Added
- `src/ipv6.cyr` — `_ipv6_parse_pure` (the prior body, factored), `_ipv6_parse_with_v4` (pre-scans for `.`, splits at the last `:` before the first dot, parses the dotted-quad via `ipv4_parse`, then synthesizes `<prefix>0:0` and feeds the pure parser, finally overwriting the trailing 4 bytes), `ipv6_parse_ex(s, out, scope_out, scope_cap)` (splits off the `%zone` suffix into a caller-owned cstr buffer, returns the zone length), `ipv6_is_v4_mapped(addr16)` (predicate for the mapped `::ffff:0:0/96` block). `ipv6_parse` keeps its old contract (no `%`, returns OK/FAIL) by forwarding to `_ipv6_parse_with_v4` after a `%`-presence check.
- `src/platform_linux.cyr` — `_lx_sockaddr_in6` gained a `scope_id` parameter (writes sin6_scope_id at offset 24). `platform_icmp6_send_to` plumbs the scope id through. `_lx_resolve_ifindex(name)` reads `/sys/class/net/<name>/ifindex` via `platform_read_file` and parses the decimal payload. `platform_resolve_ifindex(name)` is the public wrapper used from main.
- `src/probe.cyr` — `probe_run` signature: `scope_id` inserted after `addr_arg`; threaded into the v6 send path.
- `src/main.cyr` — literal-v6 branch uses `ipv6_parse_ex`; on `%zone` it resolves the ifindex and aborts the target with `yo: unknown interface: <name>` + exit 2 when the resolve fails. v4-mapped addresses (`ipv6_is_v4_mapped`) collapse to the v4 dispatch with the embedded octets repacked as a u32. Banner preserves whatever the user typed (`::ffff:127.0.0.1`, `fe80::1%lo`) because the original `target` cstr is passed straight through.
- `src/output.cyr` — `_output_is_v4_mapped` predicate; `output_ipv6_to_buf` short-circuits v4-mapped addresses to `::ffff:a.b.c.d` form per RFC 5952 §5. IPv4-compatible (`::a.b.c.d`, deprecated) keeps plain hex.
- `tests/yo.tcyr` — 67 new assertions (365 total). New groups: `ipv6_parse embedded v4` (15 — happy paths for `::ffff:1.2.3.4`, `::1.2.3.4`, `2001:db8::1.2.3.4`, full no-`::` form; rejects for bare quad, short quad, long quad, octet > 255), `ipv6_parse scope id` (12 — no-scope, `eth0`, truncation contract, bare `%` rejected, mapped+zone composite, null-ptr), `platform resolve ifindex` (2 — `lo`→1 and unknown→0). `output ipv6_to_buf` extended by 6 (v4-mapped 127.0.0.1, max-octet mapped, v4-compat stays plain). Two prior rejection lines (`::ffff:1.2.3.4` and `fe80::1%eth0`) updated to match the new contract — only the bare `ipv6_parse` rejects `%`; the `_ex` variant accepts it.

### Iron-verified
- `yo ::ffff:127.0.0.1` → banner `::ffff:127.0.0.1 (localhost)`, two replies via ICMPv4 socket, ttl=64, ~0.03 ms.
- `yo ::1%lo` → banner `::1%lo (localhost)`, two replies via ICMPv6, ttl=64.
- `yo fe80::b241:6fff:fe0c:e425%enp1s0` → real link-local probe of the host's own enp1s0 address; PTR resolves to `archaemenid8`; ~0.03 ms.
- `yo ::1%nope` → `yo: unknown interface: nope`, exit 2.
- `yo -q 127.0.0.1 ::1%lo ::ffff:127.0.0.1` → mixed v4 / link-local v6 / v4-mapped multi-target; all replies received; exit 0.

### Deferred
- Nothing from the 0.5.x band remains. Next milestone: 0.6.x AGNOS backend, still blocked on the kernel ICMP surface (r8169 RX-path 5-part bundle iron-validating, Attempt 97 pending in agnos).

## [0.5.1] — 2026-05-23

IPv6 polish. AAAA DNS lookup, `ip6.arpa` PTR reverse-DNS, `-4` / `-6` family-forcing flags, and a canonical RFC 5952 v6-address formatter for banners. `yo dns.google` still defaults to IPv4 (POSIX expectation); `yo -6 dns.google` does the AAAA route. Closes the headline gaps from 0.5.0; scope IDs and IPv4-embedded form remain deferred.

### Added
- `src/dns.cyr` — `DNS_TYPE_AAAA=28`. `_dns_build_query` gained a `qtype` parameter (callers updated). `dns_resolve_aaaa(host, out16)` issues an AAAA query; `_dns_parse_aaaa_response` walks to the first AAAA record and copies its 16-byte rdata. `_dns_build_reverse_qname_v6(addr16, buf)` emits 32 single-nibble labels least-sig-first per RFC 3596 §2.5 + `ip6.arpa.` (74 bytes total). `_dns_build_ptr_query_v6` + `dns_reverse_resolve_v6` mirror the v4 reverse path. `_dns_nibble_to_hex` helper.
- `src/cli.cyr` — `-4` / `--ipv4` and `-6` / `--ipv6` bool flags. Registry layout grew 72 B → 88 B (10 slots). New `CLI_ERR_AF_CONFLICT` when both flags are set; main.cyr surfaces `yo: -4 and -6 are mutually exclusive` on stderr and exits 2.
- `src/main.cyr` — resolution order per target: `ipv4_parse` → `ipv6_parse` → `dns_resolve` (A) → `dns_resolve_aaaa`. `-4` restricts to v4 paths; `-6` restricts to v6 paths. v6 literals now use `dns_reverse_resolve_v6` for banner parens (unless `-n`). AAAA-resolved targets get a canonical formatted address in the banner via `output_ipv6_to_buf`.
- `src/output.cyr` — `output_ipv6_to_buf(addr16, buf)` renders RFC 5952 canonical text: lowercase, longest zero-run compressed to `::` (≥2 groups only, first-of-equal-length wins), no leading zeros in groups. Buf ≥ 40 bytes. Helpers `_output_nibble_to_buf`, `_output_u16_hex_to_buf`.
- `tests/yo.tcyr` — 46 new assertions (298 total): CLI `-4`/`-6` (5), v6 reverse qname byte-shape (15), AAAA response parser (5 — happy + rdlen + qid mismatch), `output_ipv6_to_buf` (14 — `::`, `::1`, `1::`, `2001:db8::1`, Google v6, full 8-group, single-zero not compressed).

### Iron-verified
- `yo dns.google` → A path → `(8.8.8.8)`. `yo -4 dns.google` same.
- `yo -6 dns.google` → AAAA path → banner `dns.google (2001:4860:4860::8844)`, probe timeout (no global v6 route on archaemenid, same as 0.5.0).
- `yo ::1` → ip6.arpa PTR → banner `::1 (localhost)`.
- `yo -6 ::1 <ula-self>` → both v6 literals probe; ULA banner shows `(archaemenid)` from local ip6.arpa PTR.
- `yo -4 ::1` → resolution fails ("cannot resolve host: ::1") with exit 2.
- `yo -4 -6 host` → AF_CONFLICT, exit 2.

### Deferred
- Scope IDs (`fe80::1%eth0`) — needs zone-index lookup against `/sys/class/net` or netlink. Plausible in 0.5.2.
- IPv4-embedded textual form (`::ffff:1.2.3.4`) — small parser extension. Plausible in 0.5.2.

## [0.5.0] — 2026-05-23

IPv6 literal probe. `yo ::1`, `yo 2001:db8::1`, and any full eight-group form now run end-to-end ICMPv6 against the Linux backend with the same UX as the v4 path (banner + per-packet hop limit + summary, multi-target dispatch, `-c`/`-W`/`-i`/`-s`/`-q`/`-n` flags). The probe loop dispatches on address family per-target; v4 and v6 targets can mix in a single invocation (`yo ::1 1.1.1.1`).

### Added
- `src/ipv6.cyr` — strict RFC 4291 colon-hex parser. Single allowed `::`, 1-4 hex digits per group, case-insensitive, output is 16 packed bytes in network byte order. Rejects scope IDs (`fe80::1%eth0`) and IPv4-embedded textual form (`::ffff:1.2.3.4`) — both deferred to 0.5.1.
- `src/icmp.cyr` — `ICMPV6_ECHO_REQUEST=128`, `ICMPV6_ECHO_REPLY=129`, `icmp6_build_echo_request(buf, ident, seq, payload, len)`. Wire shape identical to ICMPv4 minus the checksum work; the kernel fills the cksum field on AF_INET6 SOCK_DGRAM when `IPV6_CHECKSUM` is enabled with offset=2.
- `src/platform_linux.cyr` — IPv6 constants (`AF_INET6=10`, `IPPROTO_IPV6=41`, `IPPROTO_ICMPV6=58`, `IPV6_CHECKSUM=7`, `IPV6_RECVHOPLIMIT=51`, `IPV6_HOPLIMIT=52`). New primitives: `_lx_sockaddr_in6(addr16, port)` builds the 28 B sockaddr; `_lx_enable_ipv6_checksum(fd)` sets the kernel-checksum offset; `_lx_enable_recvhoplimit(fd)` opts into hop-limit ancillary; `platform_icmp6_open` / `platform_icmp6_send_to` / `platform_icmp6_recv_ext` mirror the v4 trio; `_lx_cmsg_find_hoplimit` walks the cmsg chain for `(IPPROTO_IPV6, IPV6_HOPLIMIT)`.
- `src/probe.cyr` — `probe_run(target, af, addr_arg, banner_parens, ...)` now takes an address-family selector; v4 passes a packed u32 in `addr_arg`, v6 passes a pointer to 16 packed bytes. ICMP framing, send, recv, and reply-type acceptance all branch on `af`.
- `src/main.cyr` — resolution order per target: `ipv4_parse` → `ipv6_parse` → `dns_resolve` (A only). Reverse DNS only runs on the v4 path for this release.
- `tests/yo.tcyr` — 65 new assertions (252 total): 52 covering `ipv6_parse` (happy paths for `::`, `::1`, `1::`, `2001:db8::1`, full 8-group, uppercase + mixed case, trailing `::`, Google v6; rejects for empty, single-colon, leading/trailing single colon, double `::`, 5-digit group, 7-group-without-`::`, 9-group, `::` with full 8 groups, non-hex digit, scope-id, IPv4-embedded, null ptr) plus 13 covering `icmp6_build_echo_request` byte placement.

### Iron-verified
- `yo ::1` → ttl=64, rtt ≤ 0.1 ms.
- `yo <ula-self>` (`fd81:…:e425`) → ttl=64, rtt ≤ 0.1 ms — full eight-group hex parse.
- `yo ::1 <ula> 127.0.0.1` mixed v4+v6 → all three respond, exit 0.
- WAN IPv6 (`2001:4860:4860::8888`) was not reachable from the iron-validation host (no global v6 route on this network — confirmed by system `ping -6` also returning `Network is unreachable`); the v6 send path itself is exercised end-to-end on link-local + ULA + loopback.

### Deferred to 0.5.1
- AAAA DNS lookup for hostnames (`yo google.com` continues to resolve to IPv4 only).
- IPv6 reverse DNS (PTR via `nibble.…ip6.arpa.`).
- `-4` / `-6` flags to force address family when a hostname could resolve to both.
- Scope IDs (`fe80::1%eth0`) and IPv4-embedded textual form (`::ffff:1.2.3.4`).

## [0.4.3] — 2026-05-23

TTL / hop-limit display. Per-packet output now shows the response TTL between `seq=` and `rtt=` — fourth and final item in the 0.4.x band. With this, yo has POSIX-ping output parity on the Linux backend; next milestone is 0.5.x IPv6.

### Added
- `src/platform_linux.cyr` — `IP_RECVTTL` enabled via `_lx_enable_recvttl(fd)` right after each successful `socket()` (both SOCK_DGRAM and SOCK_RAW). New `platform_icmp_recv_ext(fd, buf, maxlen, ttl_out)` switches the recv path from `recvfrom` to `recvmsg` (syscall 47): builds a 56 B `msghdr` + 16 B `iovec` + 64 B ancillary control buffer, calls recvmsg, and writes the TTL into `*ttl_out` (0 when absent). The pure helper `_lx_cmsg_find_ttl(control, controllen)` walks the cmsg chain looking for `(IPPROTO_IP, IP_TTL)`; CMSG_ALIGN performed inline as `((clen + 7) >> 3) << 3`.
- `src/output.cyr` — `output_reply` gains a `ttl` parameter; renders `  seq=N  ttl=T  rtt=X.XX ms\n` when `ttl > 0`, omits the chunk gracefully otherwise (older kernels / non-Linux backends without ancillary TTL).
- `src/probe.cyr` — allocates a one-slot `ttl_slot` outside the probe loop, passes it to `platform_icmp_recv_ext`, then forwards the value to `output_reply`.
- `tests/yo.tcyr` — 6 new assertions (187 total) in the `cmsg ttl walk` group: single IP_TTL cmsg returns the value, non-matching level/type returns 0, second-in-chain walk respects CMSG_ALIGN(20)=24, truncated buffer rejected, `cmsg_len < 16` rejected, empty buffer returns 0.

### Behavior
- The `platform_icmp_recv` (recvfrom-only) function is retained but no longer used by the probe loop — it's kept as a thin primitive for any future caller that doesn't need ancillary data.

### Fixed
- Stray output (e.g. `570x`, `130x`, `610x`) between targets in multi-target mode and a missing/garbled trailing newline in two other sites (`yo: cannot resolve host: <name>` on stderr, and `output_summary`'s all-packets-lost branch). Root cause: under the current Cyrius toolchain, a 1-byte string literal `"\n"` passed alone to `syscall(1, fd, "\n", 1)` / `_puts("\n")` mis-binds, with strlen reading past the intended byte. Multi-character literals containing `\n` (e.g. `" ms\n"`, `"\nA"`) render correctly. Workaround: small `_emit_lf(fd)` helper in main.cyr (and an inline equivalent in output.cyr) that writes the LF byte from a stack scratch buffer. The pre-existing buggy sites had been latent since 0.3.0 (`output_summary` all-lost branch) and 0.4.0 (resolve-failure stderr); the 0.4.2 inter-target separator surfaced the visible regression that drove the diagnosis.

## [0.4.2] — 2026-05-23

Multiple targets. `yo router 8.8.8.8 1.1.1.1` now runs sequential per-target probes with a combined exit code — third item in the 0.4.x band.

### Added
- `src/main.cyr` — wraps the resolve + `probe_run` block in a loop over `cli_target_count(reg)`. Each target is independently resolved (forward DNS for hostnames, reverse DNS for literal IPs unless `-n`), probed with the same per-target settings (`-c`, `-W`, `-i`, `-s`), and gets its own banner+summary block separated by a blank line in non-quiet mode. Aggregate exit code: `0` if any target received at least one reply, `2` if no replies and any target hit a resolve/socket error, `1` otherwise.
- `src/cli.cyr` — `cli_target_count(reg)` and `cli_target_at(reg, idx)` accessors. `cli_target(reg)` retained as the singular accessor (returns the first positional). Usage line updated to `<host> [host ...]`.
- `tests/yo.tcyr` — 12 new assertions (181 total) covering multi-positional parse (3 targets, flag interleave, single-target count=1) and the new accessors.

### Behavior
- Unresolvable hosts in a multi-target list no longer abort the run — yo prints `yo: cannot resolve host: <name>` to stderr and proceeds to the next target. Process exit code still reflects the failure (2) unless another target succeeded (0).

## [0.4.1] — 2026-05-23

Reverse DNS. `yo 8.8.8.8` now banners as `yo 8.8.8.8 (dns.google) — 56 bytes` — the symmetric completion of the 0.4.0 forward-DNS work. Second item in the 0.4.x band.

### Added
- `src/dns.cyr` — `dns_reverse_resolve(packed, out, cap)` issues a PTR query against the `D.C.B.A.in-addr.arpa.` name and decodes the answer's RDATA into the caller's buffer. New helpers: `_dns_build_reverse_qname` (octets emitted least-significant-first per RFC 1035 §3.5), `_dns_build_ptr_query`, `_dns_decode_name` (compressed-pointer-aware with a 16-jump loop guard), `_dns_parse_ptr_response`. Shared `_dns_walk_to_type` factored out so forward (A) and reverse (PTR) parsing share header validation + answer walking. Shorter timeout (1 s) and 1 attempt so probe start isn't delayed when no PTR record exists.
- `src/cli.cyr` — `-n` / `--numeric` flag (POSIX-ping shape) to skip reverse lookup. Registry grew from 64 B to 72 B (8 slots).
- `src/output.cyr` — `output_ipv4_to_buf(packed, buf)` formats a packed IPv4 as a NUL-terminated cstr. `output_banner` now takes a `parens` cstr (or 0) instead of `(packed_addr, show_resolved)` — main.cyr fills the parens with the resolved IP for hostname targets or the reverse-DNS name for literal IPs.
- `src/main.cyr` — chooses the banner parens: forward path formats the resolved IPv4, reverse path calls `dns_reverse_resolve` unless `-n` was given. Reverse-lookup failure silently leaves parens empty.
- `tests/yo.tcyr` — 36 new assertions (169 total) covering reverse-QNAME bytes for single- and triple-digit octets, name decoder (uncompressed, single pointer, label-then-pointer, self-loop guard, out-of-bounds pointer, out-buf overflow), PTR response extraction, `output_ipv4_to_buf` shape, and `-n` / `--numeric` parse.

## [0.4.0] — 2026-05-23

DNS resolution. `yo <hostname>` now works — first item in the 0.4.x DNS + UX-polish band per [roadmap.md](docs/development/roadmap.md).

### Added
- `src/dns.cyr` — RFC 1035 A-record resolver. QNAME encoder, query builder, response parser (handles compressed-pointer NAMEs, walks past CNAMEs to find the first A record), and an `/etc/resolv.conf` nameserver-line parser. Falls back to `1.1.1.1` when resolv.conf is missing/empty/IPv6-only. Two attempts at 2 s SO_RCVTIMEO before giving up. Self-contained: uses `platform_udp_*` directly, no `lib/net.cyr` import (per-backend sovereignty rule).
- `src/platform_linux.cyr` — UDP primitives: `platform_udp_open`, `platform_udp_send_to(fd, packed_addr, port, ...)`, `platform_udp_recv`. New `platform_read_file(path, buf, maxlen)` for slurping `/etc/resolv.conf`. Refactored `_lx_sockaddr_in` to accept a port argument (network byte order), shared by ICMP (port=0) and UDP send paths.
- `src/output.cyr` — `_output_print_ipv4(packed)` helper. `output_banner` now takes `(target, packed_addr, show_resolved, size)`; when `show_resolved=1` the banner appends `(a.b.c.d)` after the hostname.
- `src/main.cyr` — on `ipv4_parse` failure, falls through to `dns_resolve(target)`. On success, banner shows both forms (`yo google.com (142.250.x.x)`); on failure, exits 2 with `yo: cannot resolve host: <name>`.
- `tests/yo.tcyr` — 46 new assertions (133 total) covering QNAME encoding (happy + rejects), query builder field placement, name-skip (uncompressed / pointer / oversized-label reject), response parser (single A, CNAME-then-A, ID mismatch, non-zero RCODE, QR=0, truncated, ANCOUNT=0), and `/etc/resolv.conf` parsing (tab separator, comments, indented lines, IPv6 skip, missing trailing newline).

## [0.3.0] — 2026-05-23

First working release. `yo <ipv4>` produces real ICMP echo probes on Linux.

### Architecture
- **Multi-backend pivot.** yo is no longer gated on the agnos kernel ICMP surface. `src/platform.cyr` dispatches to backend-specific implementations; `src/platform_linux.cyr` is the working Linux backend (POSIX socket: unprivileged SOCK_DGRAM ICMP, falls back to SOCK_RAW). AGNOS, Windows, Apple backends plug in later as siblings.
- **Per-backend sovereignty rule.** Linux uses POSIX `socket()` pragmatically. The AGNOS backend (future) will use sovereign `icmp_echo` / `net_send_raw` primitives. v1.0 release gate enforces no-POSIX on the AGNOS backend only.
- **`taar` stays unextracted.** Everything yo needs lives inline in `yo/src/`. Substrate extraction waits for `dig` to grow into a second consumer per the brainstorm-window pattern.

### Added
- `src/icmp.cyr` — RFC 792 ICMP echo framing + RFC 1071 Internet checksum (`icmp_checksum`, `icmp_verify`, `icmp_build_echo_request`, accessors). Checksum byte-identical to `agnos/kernel/core/net.cyr:25`.
- `src/cli.cyr` — full flag inventory (`-c -W -i -s -q -v -h` + long forms) via `lib/flags.cyr`. yo is the first consumer of `lib/flags.cyr` in the ecosystem.
- `src/ipv4.cyr` — strict dotted-quad parser. Returns packed u32 matching the kernel's `ip4()` packing.
- `src/stats.cyr` — RTT accumulator (microsecond integer math, no f64). Pure data structure.
- `src/output.cyr` — probe-time printers (`output_banner` / `output_reply` / `output_timeout` / `output_summary`). Buf-writing `_output_us_as_ms_to_buf` is unit-tested.
- `src/platform.cyr` + `src/platform_linux.cyr` — Linux backend. Raw syscalls: `socket`, `sendto`, `recvfrom`, `setsockopt`, `clock_gettime`, `nanosleep`, `close`. Self-contained; no `lib/net.cyr` import.
- `src/probe.cyr` — the probe loop. Per-packet send/recv with SO_RCVTIMEO, sleep between iterations, POSIX exit codes (0 / 1 / 2).
- **Ctrl-C handler** via signalfd. `platform_install_interrupt_watch()` blocks SIGINT + creates non-blocking signalfd; probe loop checks between iterations and breaks cleanly with summary printed. Avoids the `rt_sigaction` + `sa_restorer` trampoline that x86_64 requires without inline asm.
- `cyrius.cyml [deps].stdlib` += `args`, `flags`.
- `tests/yo.tcyr` — 87 assertions covering ICMP framing/checksum, CLI parse (defaults / short / long / errors), IPv4 parse (happy + all rejects), RTT stats, and output format byte-exactness.
- `.github/workflows/ci.yml` — added `workflow_call:` trigger so `release.yml` can invoke it as a reusable workflow gate.

### Fixed
- Trailing-byte glitch in `output_summary`: `syscall(1, 1, "\n", 1)` immediately following `_output_puts(" ms")` was dropping the newline and emitting a stray digit. Consolidated to a single `_output_puts(" ms\n")` write.

## [0.1.0]

### Added
- Initial project scaffold
