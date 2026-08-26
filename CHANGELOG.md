# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.5.10] — 2026-08-26 (toolchain 6.5.35; taar 0.5.0)

Readability/robustness only — **no behaviour change**, no probe path touched.

### Changed
- **AGNOS `platform_dns_server` now calls `sys_net_dns_server()`** instead of the raw
  `syscall(61, 3)` it shipped as in 0.5.7 (`src/platform_agnos.cyr:139`). 0.5.7 labelled
  that literal "Interim" for exactly this reason: cyrius had no wrapper, so the number
  went in bare and the entry promised to retire it once one existed. The 6.5.35 vendored
  stdlib ships it — `lib/syscalls_x86_64_agnos.cyr:1190`, with `SYS_NET_CONFIG = 61`
  at :361 and the field-0/1/2 peers `sys_net_ip` / `sys_net_netmask` / `sys_net_gateway`.
  The stdlib's own comment states the stake plainly: **#61 is `net_config` on AGNOS but
  `wait4(2)` on Linux.** The `#ifdef CYRIUS_TARGET_AGNOS` arm kept that safe, but a
  number meaning two different things on two kernels does not belong in a source file.
  This retires the last raw syscall number in yo's AGNOS backend.

  Follows the precedent the substrate lib already set (`taar/src/socket.cyr:396`), whose
  comment records the same swap for the same reason at the same pin. Deliberately held
  out of 0.5.8, which was kept a pure toolchain/dep bump with zero source edits per the
  one-change-at-a-time rule; this is that change, on its own.

### Notes
- Host **and** `--agnos` build clean; **365/365 tests** green, unchanged from 0.5.9.
- The two spellings are semantically identical — `sys_net_dns_server()` is defined as
  `syscall(SYS_NET_CONFIG, 3)`. The emitted `--agnos` binary is *not* byte-identical,
  because the wrapper is a real call rather than an inlined literal and pulls its three
  `net_config` peer into the reachable set (`--agnos` unreachable fns 421 → 420). That
  is a codegen difference, not a behavioural one.
- The swapped line sits inside the AGNOS `#ifdef`, so the host build does not exercise
  it and `cyrius test` cannot cover it — `cyrius build --agnos` is the only gate that
  proves this change, and it is clean. Unchanged from 0.5.7, the AGNOS backend still has
  no runtime validation: the ring-3 `icmp_ping` syscall gate is open, so nothing here has
  been *run* on agnos, only compiled for it.

## [0.5.9] — 2026-08-26

Soundness fix to the **test gate** itself, plus the exit-syscall portability that
came with it. No change to probe behaviour; yo's `0` / `1` / `2` exit contract is
byte-for-byte what it was.

### Fixed
- **Test entry points exited with the raw assertion-failure COUNT, so a failing suite
  could score PASS.** `assert_summary()` returns `_assert_fail` — the failure count,
  not a boolean (`lib/assert.cyr:186`, `return _assert_fail;`). A process wait status
  is only 8 bits, so exactly **256 / 512 / 768** failures truncate to exit **0** and the
  runner reports green over a broken suite. yo has 365 assertions (46 `assert` +
  299 `assert_eq` sites, many inside loops), so 256 concurrent failures is reachable,
  not theoretical. All three entry points now clamp any non-zero return to 1 before
  exiting — the shape `cyrius init` already generates
  (`cyrius/programs/cyrius-init-templates/proj-tcyr:12-17`):
  `tests/yo.tcyr`, `tests/yo.bcyr`, `tests/yo.fcyr`.

  Demonstrated both directions by injecting exactly 256 failing assertions into
  `tests/yo.tcyr`: with the old bare `syscall(60, exit_code)` the runner printed
  `365 passed, 256 failed` and then scored **`1 passed, 0 failed`, exit 0**; with the
  clamp it scores **`0 passed, 1 failed`, exit 1**. The probe was removed afterward —
  the shipped suite is unchanged at 365 assertions.

### Changed
- **Retired the hardcoded `syscall(60, …)` / `syscall(SYS_EXIT, …)` exits in favour of
  `sys_exit_group(…)`.** Two reasons, one per half of the swap:
  - *Portability.* The literal `60` is x86_64-only — exit is **93** on aarch64 and
    differs again on agnos. `sys_exit_group` is present on every peer yo targets:
    `lib/syscalls_linux_common.cyr:176`, `lib/syscalls_x86_64_agnos.cyr:471`,
    `lib/syscalls_windows.cyr:136`. Same class of bug as the v5.4.11 aarch64 syscall
    split that this stdlib already carries a warning about.
  - *Correctness.* `sys_exit` is `exit(2)`, which ends only the **calling thread**;
    `exit_group(2)` ends the **process**. Single-threaded today, but the wrong one of
    the two is a latent hang, not a style preference.

  Applied to the three test entry points above and to the two source exits —
  `src/main.cyr:199` and `src/test.cyr:12`. **No clamp on `src/main.cyr`**: its
  `0` (reply) / `1` (no reply) / `2` (error) are the documented POSIX-ping exit
  contract, all well under 256, and clamping them would flatten a real distinction.

### Notes
- `cyrius test` **365/365, exit 0**; a deliberately broken assertion now reports
  `FAIL` and exits **1**. Host **and** `--agnos` builds clean. `cyrius bench` and
  `cyrius fuzz` both compile and run green (exit 0) with the new epilogue.
- Exit contract re-verified against the built binary, not just the source:
  `yo -c 1 127.0.0.1` → 0, `yo -c 1 ::1` → 0, `yo -c 1 192.0.2.1` (timeout) → 1,
  `yo -c 1 <unresolvable>` → 2.
- Held out of **0.5.8** deliberately — that release was a pure toolchain/dep bump with
  zero source edits, per CLAUDE.md's "ONE change at a time" rule.

## [0.5.8] — 2026-08-26 (toolchain 6.5.35; taar 0.5.0)

Pure toolchain + dependency bump — **no source edits, no behaviour change**.

### Changed
- **Toolchain pin 6.2.24 → 6.5.35.** Three minor bands (6.3.x, 6.4.x, 6.5.x) in one
  step. Verified source-clean *before* building, by diffing cyrius's own
  `docs/api-surface.snapshot` between the two tags, filtered to the eleven stdlib
  modules yo declares: the surface grew **219 → 280 symbols with zero removals and
  zero arity changes**. Nothing yo calls moved. This also clears the
  `cyrius.cyml pins 6.2.24 but cycc is 6.5.35` drift warning — 6.2.24 was no longer
  installed locally, so the pin had stopped describing what actually compiled yo.
- **`taar` dep 0.3.1 → 0.5.0.** yo consumes exactly one taar symbol — `ipv4_parse`
  (`src/dns.cyr:287`, `src/main.cyr:91`, `src/ipv6.cyr:163`) — and it is byte-identical
  across the bump. Everything 0.4.0/0.5.0 changed lives in the `socket`/`dns` half of
  the bundle that DCEs out of yo's binary: AGNOS `taar_tcp_recv` now reports a deadline
  expiry as `_TAAR_ERR_TIMEOUT` instead of collapsing it into `0`, plus a DNS TCP
  fallback on truncation. taar 0.5.0 is itself pinned to 6.5.35, so this bump also puts
  yo and its substrate back on one toolchain.
- **Vendored stdlib snapshot refreshed** — 23 of 27 `lib/*.cyr` changed hash
  (`cyrius.lock`); no files added or removed. `args_agnos.cyr`, `args_win.cyr`,
  `flags.cyr` and `str.cyr` were already current.

### Notes
- Host **and** `--agnos` build clean; **365/365 tests** green, unchanged from 0.5.7.
  `cyrius bench` (`tests/yo.bcyr`) and `cyrius fuzz` (`tests/yo.fcyr`) also compile and run
  green at this pin — neither is wired into CI, which gates only `deps`/`build`/`test`.
- Smoke-tested on archaemenid across every resolution path, not just the compile:
  `yo 127.0.0.1` and `yo ::1` (ttl + reverse DNS → `(localhost)`), `yo dns.google`
  (forward A — the live `ipv4_parse` call site), `yo ::1%lo` (scope id), and
  `yo ::ffff:127.0.0.1` (v4-mapped → ICMPv4 dispatch). All exit 0 with replies.
- Build grew to ~145 KB (148,120 B) pre-DCE, 400 unreachable fns (was 349 on the prior
  snapshot). The growth is the larger vendored stdlib plus taar's 979-line bundle — all
  of it DCE-eligible (`CYRIUS_DCE=1`), none of it reachable.

### Known latent (found while verifying the bump, not introduced by it)
- **`cyrius build --aarch64` returns OK and must not be trusted.** `src/platform_linux.cyr:20-32`
  hardcodes x86_64 syscall numbers (`_LX_SYS_SENDTO = 44`, `_LX_SYS_OPEN = 2`, …). The aarch64
  backend remaps only numbers it holds constants for, and the 6.5.35 aarch64 peer
  (`lib/syscalls_aarch64_linux.cyr`) has **no `SYS_SENDTO` at all** — so `44` would arrive as
  `fstatfs(2)`. taar hit exactly this and documented it at its 0.3.3: a clean `--aarch64` build
  whose `taar_udp_send` silently ran `fstatfs` and scribbled a `struct statfs` over the query
  buffer. **yo ships x86_64 only, so this is latent, not live.** If an aarch64 target is ever
  added, route `platform_linux.cyr` through the arch-dispatched stdlib wrappers (`sys_socket`,
  `sys_sendto`, `sys_recvfrom`, …) rather than raw numbers, and add a CI leg that *runs* the
  binary under `qemu-aarch64` — a build-only leg cannot catch this.
- **The three test entry points don't clamp their exit code.** `assert_summary()` returns the raw
  failure *count* (`lib/assert.cyr:186`), and `tests/yo.tcyr` ends in a bare `syscall(60, exit_code)`.
  A wait status is 8 bits, so exactly 256/512/768 failures would exit 0 and score PASS. yo has 365
  assertions, so 256 is reachable. Not hit here — this release failed 0 — but the gate is not sound.
  `cyrius init`'s current template clamps (`if (exit_code > 0) { exit_code = 1; }`) and uses
  `sys_exit_group`, which is also the portable spelling (`60` is x86_64-only). Left for its own
  change per the one-change-at-a-time rule.

### Documentation
- **`docs/development/state.md`: AGNOS gate #1 is closed and has been for some time.**
  The blocker section (written 2026-06-03 against pin 6.0.51) claimed `cyrius/lib/args.cyr`
  had no `CYRIUS_TARGET_AGNOS` branch, so an agnos build would see zero args. Checked
  against the live vendored source: `lib/args.cyr:99` dispatches to `lib/args_agnos.cyr`,
  which recovers argc/argv from the SysV init stack via an entry-parked `r15` (cyrius
  6.0.87 / 6.1.32). Its hash is *unchanged* by this bump — it was already present at the
  6.2.24 pin, so the doc was stale rather than newly outdated. **The remaining AGNOS gate
  is the ring-3 `icmp_ping`/UDP/ifindex syscall surface in agnos, alone.**
- state.md was also still headed "0.5.6" — it never got its 0.5.7 refresh. Now current.


## [0.5.7] — 2026-06-23

### Changed
- **AGNOS nameserver selection prefers the kernel-leased DNS server.** On agnos,
  `_dns_choose_nameserver` (`src/dns.cyr`) now calls the new **`net_config(3)`#61**
  syscall first via `platform_dns_server` (`src/platform_agnos.cyr`) — the DHCP
  option-6 on-subnet resolver — and uses it when `> 0`, before `/etc/resolv.conf` and
  the `1.1.1.1` fallback. The off-subnet fallback needs working gateway routing the
  kernel can't guarantee on real iron (it froze `yo google.com` on archaemenid).
  Linux's `platform_dns_server` returns `0`, so the `/etc/resolv.conf` path is
  unchanged there. Interim raw `syscall(61, 3)`. **Requires agnos ≥ 1.45.16.**
- **`taar` dep 0.3.0 → 0.3.1** — the regenerated `dist/taar.cyr` bundle (carries taar's
  matching kernel-leased-resolver path); yo still consumes only the `ipv4_*` codec, so
  no API change to yo's surface (the new `socket`/`dns` modules DCE out of yo's binary).

## [0.5.6] — 2026-06-19 (toolchain 6.2.24; taar 0.3.0)

### Changed
- **Toolchain pin 6.2.6 → 6.2.24.** Build + tests green on the current wrapper;
  resolves the manifest-pin/wrapper drift (`cyrius --version` no longer warns).
- **`taar` dep 0.1.0 → 0.3.0.** taar grew its socket + DNS substrate (whirl
  extraction) and an AGNOS socket backend; yo still consumes only the pure
  IPv4 codec, so the bump is the regenerated `dist/taar.cyr` bundle (now 656
  lines, vendored to `lib/taar.cyr` via `cyrius deps`) with no API change to the
  `ipv4_*` surface yo uses. The new `socket`/`dns` modules ride along in the
  bundle and DCE out of yo's binary.

### Notes
- Host + `--agnos` both build clean; **365/365 tests** green. Pure dep/toolchain
  bump — no behavior change, no QEMU re-smoke needed.

## [0.5.5] — 2026-06-15 (fold onto taar — IPv4 codec extracted)

### Changed
- **`src/ipv4.cyr` removed; folds onto `taar` 0.1.0.** yo and `dig` shipped a
  byte-identical IPv4 parser — the documented extraction trigger. The codec
  now lives in `taar/src/ipv4.cyr` (and gains `ipv4_format_to_buf`, which yo
  didn't carry before); yo pulls it via `[deps.taar]` (`path = "../taar"` for
  local dev, `git`+`tag` published fallback) and `include "lib/taar.cyr"` in
  `src/main.cyr`. No behavior change — `ipv4` is pure code (no syscalls), so
  the AGNOS backend (`platform_agnos.cyr`) is unaffected.

### Notes
- Host + `--agnos` both build clean; **365/365 tests** green. Pure-code
  refactor — no QEMU re-smoke needed; the 0.5.4 ICMP-on-agnos result stands.

## [0.5.4] — 2026-06-14 (pin → 6.2.6; drop the chrono workaround)

### Changed
- **Toolchain pin 6.2.5 → 6.2.6.** cyrius 6.2.6 bound chrono's agnos monotonic clock + sleep to the real kernel
  syscalls and added `sys_uptime_ms`(#40) / `sys_sleep_ms`(#41) peer wrappers (the fix for the gap `dig`/`yo`
  surfaced — cyrius issue `2026-06-14-chrono-agnos-monotonic-sleep-stale-stubs.md`).
- **`src/platform_agnos.cyr` drops the direct `syscall(40)/(41)` workaround** → uses the `sys_uptime_ms`/
  `sys_sleep_ms` wrappers (`platform_now_us`, `platform_sleep_ms`, and the UDP-recv poll-loop deadline).
- Dropped the regenerated stale `lib/` again (a 6.2.5-era vendored snapshot shadowed the 6.2.6 stdlib); the build
  uses the version-pinned snapshot.

## [0.5.3] — 2026-06-14 (AGNOS breakout — yo builds for the sovereign kernel)

### Added
- **`src/platform_agnos.cyr` — the AGNOS backend.** Replaces the POSIX `socket()` path with the sovereign ring-3
  syscalls via the `CYRIUS_TARGET_AGNOS` peer (cyrius ≥ 6.2.3). **The ICMP model bridge**: AGNOS exposes
  `icmp_echo`(#55) as a *one-shot* primitive (send + wait + return RTT in one blocking call), so yo's POSIX-shaped
  `icmp_open → send_to → recv_ext` surface is collapsed — `send_to` stores the request, `recv_ext` calls
  `icmp_echo` and then **echoes the stored request back** as the reply (flip type 8→0, recompute the RFC-1071
  checksum via yo's own `icmp_checksum`) so yo's parser sees a valid echo-reply matching its id/seq/payload; RTT is
  measured host-side across `send_to..recv_ext`. DNS resolution rides the UDP peer (`udp_bind`/`send`/`recv`/
  `unbind` #51-54). IPv6-ICMP / ifindex / interrupt-watch report unavailable (no AGNOS ring-3 surface yet).
  `src/platform.cyr` dispatches `#ifdef CYRIUS_TARGET_AGNOS`. **yo now builds for AGNOS** (`cyrius build --agnos`).

### Changed
- **Toolchain pin 6.0.51 → 6.2.5** (the cyrius release carrying the AGNOS net peer).
- **Dropped the stale committed `lib/`** (81-file vendored snapshot that shadowed the 6.2.5 snapshot — the
  reference tools don't vendor `lib/`). yo now uses the version-pinned stdlib snapshot.

### Notes
- Worked around a cyrius-side gap: chrono's agnos `clock_now_ms`/`sleep_ms` are stale stubs — the backend calls
  `uptime_ms`#40 / `sleep_ms`#41 directly until chrono's agnos branch binds them.
- One pre-existing `_LX_SYS_WRITE` leak in `probe.cyr`'s error path is satisfied in the agnos backend (write is
  also syscall #1 on AGNOS; the branch is dead there); flagged for a stdlib-routing cleanup.

### Changed
- Toolchain pin bumped `cyrius = "6.0.1"` → `"6.0.51"` in `cyrius.cyml` (resolves the wrapper-vs-manifest drift; installed toolchain was already 6.0.51). Build + all 365 test assertions green on 6.0.51, no source changes required.

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
