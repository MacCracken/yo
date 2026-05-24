# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Pivot — multi-backend (2026-05-23)
- yo is no longer blocked on the agnos kernel ICMP surface. New architecture: `src/platform.cyr` is a thin dispatch shim; `src/platform_linux.cyr` is the working Linux backend (POSIX socket, unprivileged SOCK_DGRAM ICMP with SOCK_RAW fallback). The AGNOS backend slots in later as a sibling file with no changes to the call sites in `src/probe.cyr`.
- Per-backend sovereignty rule: Linux uses POSIX socket() pragmatically; AGNOS backend (future) uses sovereign primitives. v1.0 gate enforces no-POSIX on the AGNOS backend only.
- Substrate library `taar` not extracted yet — waits for `dig` to grow into a second consumer. Everything yo needs lives inline in `yo/src/`.

### Added
- `src/platform_linux.cyr` — Linux backend. SOCK_DGRAM ICMP with SOCK_RAW fallback, `sendto`/`recvfrom`/`clock_gettime`/`nanosleep` via raw syscalls. Self-contained; no `lib/net.cyr` import.
- `src/platform.cyr` — dispatch shim. Today: `include "src/platform_linux.cyr"`. Later: `#ifdef CYRIUS_TARGET_*` branches.
- `src/probe.cyr` — the probe loop. `probe_run(target, packed_addr, count, timeout_ms, interval_ms, size, quiet)` runs the full sequence, returns POSIX exit code (0 any reply / 1 all lost / 2 socket-open failure).
- `src/main.cyr` — wired the probe loop in. Literal IPv4 targets now produce real RTT measurements; hostnames still print the DNS-pending message (will roll inline when DNS lands).
- `src/icmp.cyr` — RFC 792 ICMP echo framing (`icmp_build_echo_request`, type/code/ident/seq/cksum accessors) and RFC 1071 Internet checksum (`icmp_checksum`, `icmp_verify`). Pure code, no syscalls — slots into the kernel ICMP surface when AGNOS backend lands.
- `src/cli.cyr` — CLI registry + parse over `lib/flags.cyr`. Owns `-c/-W/-i/-s/-q/-v/-h` (plus matching long forms) and the v0.3.x defaults (count=4, timeout=1000ms, interval=1000ms, size=56). Validation rejects negative ints and missing target.
- `src/main.cyr` — orchestration: parse argv → dispatch help/usage/errors → print planned-probe banner pointing to the pending kernel surface. Exit codes 0/2 per POSIX usage convention. Banner branches on dotted-quad vs hostname target.
- `src/ipv4.cyr` — strict dotted-quad parser. `ipv4_parse(cstr)` returns packed u32 on success (matching `agnos/kernel/core/net.cyr:21` ip4 packing) or `IPV4_PARSE_FAIL` sentinel on any rejection. No hostname/DNS path — that's roadmap 0.3.x.
- `src/stats.cyr` — RTT accumulator. Microsecond integer math (no f64). `stats_record_reply(s, rtt_us)`, `stats_record_loss(s)`, accessors for sent/recv/min/max/avg/loss-pct. Pure data structure; formatting lives in `src/output.cyr`.
- `src/output.cyr` — probe-time printers. `output_banner(target, size)`, `output_reply(seq, rtt_us)`, `output_timeout(seq)`, `output_summary(stats)` — full per-packet + summary output matching the README block. Format helper `_output_us_as_ms_to_buf` is buf-writing for unit-testability without stdout capture.
- `cyrius.cyml [deps].stdlib` += `args`, `flags`.
- `tests/yo.tcyr` — now 87 assertions: ICMP framing/checksum, CLI parse, IPv4 parse, RTT stats, and `output_us_as_ms` byte-exact format tests covering carry, rounding boundary, zero, and large values.

### Changed
- `src/stats.cyr` — printer surface moved out to `src/output.cyr` (`stats_print_summary` → `output_summary`). Keeps stats as pure data so the eventual probe loop can drive it without touching stdout.

## [0.1.0]

### Added
- Initial project scaffold
