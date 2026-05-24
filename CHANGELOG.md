# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
