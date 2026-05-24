# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
