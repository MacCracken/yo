# yo — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-08-26 (0.5.8 — toolchain pin → 6.5.35, taar dep → 0.5.0; host + `--agnos` build clean, 365/365 tests green, every resolution path smoke-tested on iron). **AGNOS gate #1 is CLOSED** — `cyrius/lib/args.cyr:99` has had a `CYRIUS_TARGET_AGNOS` branch (→ `lib/args_agnos.cyr`, argc/argv off the SysV init stack via an entry-parked `r15`) since cyrius 6.0.87/6.1.32; the § AGNOS blocker text below asserted the opposite and was stale, not wrong-when-written. The sole remaining gate is the ring-3 `icmp_ping`/UDP/ifindex syscall surface in agnos. Skipped a 0.5.7 refresh, so this covers two releases. Prior refresh 2026-06-03 (toolchain pin → 6.0.51; **AGNOS blocker re-assessed against the live cyrius + agnos *source*, not agnos's stale state.md** — the old "r8169 Attempt 97 pending" framing is dead: iron RX is proven, the kernel already has the ICMP logic in-tree, and Cyrius already has a working `CYRIUS_TARGET_AGNOS` emit target. The real, *narrow* gates are now: a `CYRIUS_TARGET_AGNOS` branch in `cyrius/lib/args.cyr`, and promoting the kernel's `icmp_ping` to a ring-3 syscall. See § AGNOS blocker for the code-grounded breakdown). 0.5.2 cut (scope IDs + IPv4-embedded textual form) was 2026-05-23; 0.5.x band closed.

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.5.8** — toolchain 6.5.35 + taar 0.5.0 dep bump (0.5.7: AGNOS kernel-leased DNS; 0.5.5: IPv4 codec folded onto taar) |
| Status | **Linux MVP at full POSIX-ping output parity for v4 + v6** — `yo dns.google` (A default), `yo -6 dns.google` (AAAA), `yo ::1` (ip6.arpa PTR → `(localhost)`), `yo fe80::<self>%enp1s0` (link-local via scope id), `yo ::ffff:127.0.0.1` (v4-mapped routed through ICMPv4). AGNOS backend now gated on **one** narrow item — exposing the kernel's existing `icmp_ping` (plus UDP + ifindex) as ring-3 syscalls (see § AGNOS blocker). The Cyrius agnos *target itself already works*, and its `args.cyr` gate closed at cyrius 6.0.87/6.1.32. 0.5.x band closed. |
| Build size | ~145 KB (148,120 B) pre-DCE; 400 unreachable fns in main. Grew from ~117 KB with the refreshed stdlib snapshot + taar's 979-line bundle — all DCE-eligible (`CYRIUS_DCE=1`), none reachable |
| Cyrius pin | 6.5.35 |
| Tests | 365 assertions in `tests/yo.tcyr` — adds IPv4-embedded parsing, scope-id parsing (`ipv6_parse_ex`), v4-mapped output formatter, `platform_resolve_ifindex` against `/sys/class/net/lo` |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | First entry in network-tools family |
| Backends | Linux (working) · AGNOS (planned) · Windows/Apple (post-1.0) |

## In-flight work

**0.5.2 scope IDs + IPv4-embedded textual form landed** — closes the 0.5.x band. `yo fe80::<addr>%enp1s0` resolves the zone via `/sys/class/net/<iface>/ifindex` and writes sin6_scope_id; `yo ::ffff:1.2.3.4` parses as v4-mapped and dispatches via the ICMPv4 socket path (ICMPv6 can't carry a v4 probe — kernel won't auto-translate). RFC 5952 §5 v4-mapped output for DNS-resolved AAAA targets that happen to be mapped. Modules touched in 0.5.2:

- `src/ipv6.cyr` — body factored into `_ipv6_parse_pure`. `_ipv6_parse_with_v4` adds dotted-quad-tail support via a pre-scan + synthetic `<prefix>0:0` rewrite and last-4-byte overwrite. `ipv6_parse_ex(s, out, scope_out, scope_cap)` splits the `%zone` suffix; returns zone length (0 if absent). `ipv6_is_v4_mapped(addr16)` predicate.
- `src/platform_linux.cyr` — `_lx_sockaddr_in6` gained `scope_id` (sin6_scope_id at off 24). `platform_icmp6_send_to` plumbs it. New `_lx_resolve_ifindex` (reads `/sys/class/net/<name>/ifindex` + decimal parse) + public `platform_resolve_ifindex`.
- `src/probe.cyr` — `probe_run(target, af, addr_arg, scope_id, banner_parens, ...)` — scope inserted after addr.
- `src/main.cyr` — literal-v6 path calls `ipv6_parse_ex`, resolves the zone via `platform_resolve_ifindex`, errors with `yo: unknown interface: <name>` (exit 2) on lookup failure. Mapped addresses route to the v4 dispatch.
- `src/output.cyr` — `_output_is_v4_mapped` predicate; `output_ipv6_to_buf` emits `::ffff:a.b.c.d` when matched.
- `tests/yo.tcyr` — 67 new assertions (365 total): `ipv6_parse embedded v4` (15), `ipv6_parse scope id` (12), `platform resolve ifindex` (2), `output ipv6_to_buf` v4-mapped extension (6).

**Iron-verified**: see 0.5.2 CHANGELOG entry. Highlights — `yo ::ffff:127.0.0.1` works via v4 dispatch; `yo fe80::b241:6fff:fe0c:e425%enp1s0` reaches the host's own link-local with PTR resolving to `archaemenid8`; mixed `yo 127.0.0.1 ::1%lo ::ffff:127.0.0.1` exits 0 with replies on all three; `yo ::1%nope` cleanly errors with exit 2.

**0.5.1 IPv6 polish** (carryover) — AAAA DNS lookup, `ip6.arpa` PTR reverse-DNS, `-4` / `-6` family-forcing flags, RFC 5952 canonical v6 banner formatter. `yo dns.google` defaults to A (POSIX expectation); `yo -6 dns.google` resolves AAAA and banners `dns.google (2001:4860:4860::8844)` even though probing then times out for lack of global v6 route. `yo ::1` banners `::1 (localhost)` via ip6.arpa. Modules from 0.5.1:

- `src/dns.cyr` — `DNS_TYPE_AAAA=28`. `_dns_build_query` takes a `qtype` arg. New `dns_resolve_aaaa`, `_dns_parse_aaaa_response`, `_dns_build_reverse_qname_v6` (32 nibble labels + `ip6.arpa.`), `_dns_build_ptr_query_v6`, `dns_reverse_resolve_v6`, `_dns_nibble_to_hex`.
- `src/cli.cyr` — `-4`/`--ipv4` and `-6`/`--ipv6` bool flags; registry 72 B → 88 B; new `CLI_ERR_AF_CONFLICT`.
- `src/main.cyr` — dispatch is now `ipv4_parse` → `ipv6_parse` → `dns_resolve(A)` → `dns_resolve_aaaa`, restricted by `-4`/`-6`. v6 reverse DNS hooked in. AAAA banner uses the canonical formatter.
- `src/output.cyr` — `output_ipv6_to_buf` (RFC 5952), helpers `_output_nibble_to_buf` / `_output_u16_hex_to_buf`.
- `tests/yo.tcyr` — 46 new assertions across CLI `-4`/`-6`, v6 reverse qname, AAAA parser, v6 canonical banner.

**0.5.0 IPv6 literal probe** (carryover) — `yo ::1`, `yo 2001:db8::1`, any full eight-group form now run end-to-end against the Linux backend with the same UX as the v4 path. Address family is dispatched per-target so a single invocation can mix v4 and v6 (`yo ::1 1.1.1.1`). On AF_INET6 SOCK_DGRAM ICMPv6 the kernel computes the outbound checksum (we enable `IPV6_CHECKSUM` with offset=2) and surfaces the inbound hop limit via cmsg (we enable `IPV6_RECVHOPLIMIT`). Modules from 0.5.0:

- `src/ipv6.cyr` — new file. Strict RFC 4291 colon-hex parser, output 16 bytes network-order. Single `::`, 1-4 hex digits per group, case-insensitive. Rejects scope IDs and IPv4-embedded textual form (deferred to 0.5.1).
- `src/icmp.cyr` — added `ICMPV6_ECHO_REQUEST=128` / `_REPLY=129` + `icmp6_build_echo_request` (wire shape identical to v4, checksum left zero for kernel fill).
- `src/platform_linux.cyr` — `AF_INET6`, `IPPROTO_IPV6`, `IPPROTO_ICMPV6`, `IPV6_CHECKSUM`, `IPV6_RECVHOPLIMIT`, `IPV6_HOPLIMIT`. New `_lx_sockaddr_in6` (28 B), `_lx_enable_ipv6_checksum`, `_lx_enable_recvhoplimit`, `platform_icmp6_open` / `_send_to` / `_recv_ext`, `_lx_cmsg_find_hoplimit`.
- `src/probe.cyr` — `probe_run(target, af, addr_arg, banner_parens, ...)` dispatches v4 vs v6 builders/sockets. `addr_arg` is interpreted by `af`: i64 packed for v4, 16-byte pointer for v6.
- `src/main.cyr` — resolution order: `ipv4_parse` → `ipv6_parse` → `dns_resolve` (A only). Reverse DNS still v4-only.
- `tests/yo.tcyr` — 65 new assertions across the `ipv6_parse valid` / `ipv6_parse invalid` / `icmp6_build_echo_request` groups.

**Iron-verified**: `yo ::1` (ttl=64, rtt ≤ 0.1 ms), `yo <ula-self>` full eight-group, mixed v4+v6 multi-target. WAN IPv6 (`2001:4860:4860::8888`) not testable from archaemenid — the network has no global v6 route (`ping -6` system tool also returns "Network is unreachable" against the same address). The v6 transmit path is verified end-to-end on loopback + ULA, which exercises every byte of the platform layer.

**0.4.3 TTL display** (carryover) — `yo 1.1.1.1` banners `seq=0  ttl=57  rtt=5.83 ms`. Linux's `IP_RECVTTL` socket option enabled on the ICMP socket; the recv path switched from `recvfrom` to `recvmsg` (syscall 47) to carry the cmsg chain; a pure helper walks the chain to find `(IPPROTO_IP, IP_TTL)`. When the kernel doesn't surface a TTL cmsg (older kernels / SOCK_RAW edge cases) the ttl chunk is omitted gracefully. Modules from 0.4.3:

- `src/platform_linux.cyr` — added `SYS_RECVMSG=47`, `IPPROTO_IP=0`, `IP_TTL=2`, `IP_RECVTTL=12` constants. `_lx_enable_recvttl(fd)` sets the socket option after each successful `socket()`. New `platform_icmp_recv_ext(fd, buf, maxlen, ttl_out)` builds a 56 B msghdr + 16 B iovec + 64 B control buffer, calls recvmsg, walks via `_lx_cmsg_find_ttl(control, controllen)` (pure, unit-tested).
- `src/probe.cyr` — calls `platform_icmp_recv_ext` instead of `platform_icmp_recv`; holds a `ttl_slot` outside the loop and threads the captured value into `output_reply`.
- `src/output.cyr` — `output_reply(seq, ttl, rtt)`; inserts `  ttl=T` between `seq=` and `rtt=` when `ttl > 0`.
- `tests/yo.tcyr` — new `cmsg ttl walk` group with 6 assertions.

**0.4.2 multiple targets** (carryover) — `yo router 8.8.8.8 1.1.1.1` runs each target sequentially with its own banner + summary block, separated by a blank line (non-quiet mode). Unresolvable hosts in the list no longer abort the run; stderr emits `yo: cannot resolve host: <name>` and the loop continues. Aggregate exit code: `0` if any target had any reply, `2` if no replies and any target hit a resolve/socket error, `1` otherwise. Modules from 0.4.2:

- `src/main.cyr` — the resolve + `probe_run` block is now wrapped in `while (i < cli_target_count(reg))`. Tracks `any_reply` / `any_error` flags to compose the final exit code. Reuses a single `parens_buf` across iterations; the DNS path overwrites in place.
- `src/cli.cyr` — added `cli_target_count(reg)` and `cli_target_at(reg, idx)`. Usage line updated to `<host> [host ...]`. Registry layout unchanged (72 B).
- `tests/yo.tcyr` — `cli multiple targets` group: 12 assertions over 3 fixtures (three targets, flag-interleaved, single-target).

**0.4.1 reverse DNS** (carryover) — `yo 8.8.8.8` → `yo 8.8.8.8 (dns.google) — 56 bytes ...`. PTR query against `D.C.B.A.in-addr.arpa.` with a shorter 1 s timeout / 1 attempt (most IPs NXDOMAIN; long timeouts would drag probe start). `-n` / `--numeric` flag suppresses the lookup. Modules from 0.4.1:

- `src/dns.cyr` — new helpers: `_dns_build_reverse_qname` (octets least-significant-first per RFC 1035 §3.5), `_dns_build_ptr_query`, `_dns_decode_name` (compressed-pointer-aware, 16-jump loop guard), `_dns_parse_ptr_response`. Shared `_dns_walk_to_type` factored out — forward and reverse parsers now share header validation + answer walking.
- `src/cli.cyr` — `-n` / `--numeric` flag; registry grew 64 B → 72 B.
- `src/output.cyr` — `output_ipv4_to_buf` formats packed IPv4 as cstr. `output_banner` now takes a `parens` cstr (or 0); main.cyr fills it with the resolved IP for hostnames or the reverse-DNS name for literal IPs.

**0.4.0 forward DNS** (carryover) — `yo <hostname>` resolver: A-records only, single UDP query to the first nameserver in `/etc/resolv.conf` (fallback `1.1.1.1`), 2 attempts at 2 s SO_RCVTIMEO. NXDOMAIN exits 2 with `yo: cannot resolve host: <name>`. Core modules:

- `src/dns.cyr` — `dns_resolve` + qname/query/response primitives + `/etc/resolv.conf` line parser. Self-contained; uses `platform_udp_*` directly per the per-backend sovereignty rule.
- `src/platform_linux.cyr` — UDP primitives (`platform_udp_open` / `_send_to(fd, addr, port, ...)` / `_recv`) + `platform_read_file`. `_lx_sockaddr_in` takes a port arg shared by ICMP (port=0) and UDP.

**0.3.0 carryover** (still the underlying Linux MVP):

- `src/platform.cyr` + `src/platform_linux.cyr` — Linux backend. SOCK_DGRAM ICMP with SOCK_RAW fallback. Raw syscalls (`open=2`, `read=0`, `sendto=44`, `recvfrom=45`, `clock_gettime=228`, `nanosleep=35`, `socket=41`, `close=3`, `setsockopt=54`, `signalfd4=289`).
- `src/probe.cyr` — probe loop. Per-packet send/recv with SO_RCVTIMEO; sleep between iterations; per-packet output + summary; passes `show_resolved` flag through to the banner.
- `src/icmp.cyr` — RFC 792 framing + RFC 1071 checksum. Already wired through the probe loop. Will stay byte-identical for the AGNOS backend.
- `src/cli.cyr` — flag inventory. First consumer of `lib/flags.cyr` in the ecosystem.
- `src/ipv4.cyr` — strict dotted-quad parser. Matches `agnos/kernel/core/net.cyr:21` `ip4()` packing.
- `src/stats.cyr` + `src/output.cyr` — RTT accumulator + README-shaped output.

**0.5.x band CLOSED with 0.5.2** — full POSIX-ping output parity for v4 + v6, literals + hostnames, both directions of DNS, with `-4`/`-6` family forcing, scope IDs for link-local, and v4-mapped textual form. Next milestone: **0.6.x AGNOS backend** — needs a sovereign equivalent of `platform_icmp_recv_ext` / `platform_icmp6_recv_ext` (cmsg-or-equivalent surface for TTL/hop-limit), sovereign UDP for the DNS path, and a sovereign ifindex resolver. See [`roadmap.md`](roadmap.md) for the full path to 1.0.

**AGNOS blocker — real status (re-assessed 2026-06-03 against live cyrius + agnos *source*; the prior write-ups parroted agnos's stale state.md and were wrong twice over).** What's actually true in the code:

- **iron RX is NOT the blocker.** The old "blocked on r8169 RX-path 5-part bundle, Attempt 97 pending" framing is dead: the bundle landed, the RxConfig root cause was found (legacy `0xE700` profile vs the VER_46 `0xCF00` — `RX_EARLY_OFF` left clear, dropping large frames mid-DMA), **broadcast RX is proven on iron** (agnos 1.32.5 bite-7), and DHCP/router association reached the box on the 1.40.x burns.
- **the kernel ICMP algorithm is NOT the blocker.** `icmp_ping(dst_ip) → rtt_ticks` + `net_handle_icmp` already exist in `agnos/kernel/core/net_icmp.cyr` — the focused echo→rtt shape yo's roadmap anticipated.
- **the Cyrius agnos target is NOT missing.** `CYRIUS_TARGET_AGNOS=1` is a *working emit target* (`cyrius/src/main.cyr:1166`) — x86_64 ELF against the agnos syscall ABI, with real stdlib peers `lib/syscalls_x86_64_agnos.cyr` (sys_read/write/exit/open/close/mmap) + `lib/alloc_agnos.cyr`, selected via `#ifdef CYRIUS_TARGET_AGNOS` in `lib/syscalls.cyr:76`. `lib/io.cyr` already works on this target (routes through `sys_read`/`sys_write`; only `flock` is Linux-gated, and yo doesn't use it).

The two **narrow, real** gates, both grounded in code:

1. **~~`cyrius/lib/args.cyr` has no agnos branch.~~ CLOSED — verified 2026-08-26 against the vendored source at pin 6.5.35.** `lib/args.cyr:99` now reads `#ifdef CYRIUS_TARGET_AGNOS` → `include "lib/args_agnos.cyr"`, which recovers argc/argv from the SysV init stack the agnos kernel builds at exec (`elf_load_from_file`): cycc emits `mov r15, rsp` as the first runtime instruction on the agnos target and reserves r15 from regalloc, so the init `rsp` survives to the readers. Landed cyrius 6.0.87 (getenv/envp) + 6.1.32 (the r15 landing park, replacing the 6.1.14 scheme that captured *after* gvar-init and so read `argc == 0`). Its `cyrius.lock` hash is **unchanged** by the 6.5.35 bump — it was already present under the 6.2.24 pin, so this entry was stale for several releases rather than newly outdated. Kept visible rather than deleted because two prior refreshes asserted it as open.
2. **`icmp_ping` is not yet a ring-3 syscall.** It has only in-kernel callers (`agnos/kernel/core/selftests.cyr:112`, in-kernel `shell.cyr:989`); nothing in `agnos/kernel/core/syscall.cyr` exposes it. agnos must promote ICMP — plus UDP (DNS) and an ifindex lookup — into its sovereign ABI. The *logic* exists, so this is plumbing, not algorithm.

Pending later:
- **AGNOS backend** (`src/platform_agnos.cyr`) — gated on the *one* remaining item above (ICMP/UDP/ifindex ring-3 syscalls), NOT on iron, the kernel ICMP algorithm, a missing Cyrius target, or argv (that gate closed). Slots in as a sibling to `platform_linux.cyr` with no changes to `probe.cyr`. Will also need the sovereign UDP surface for the AGNOS-side `dns_resolve`.
- **`taar` substrate extraction** — waits for `dig` to grow into a real second consumer.

## Dependencies (current)

**stdlib** (`cyrius.cyml [deps].stdlib`, 11 leaves — unchanged since the CLI landed):

```
string fmt alloc io vec str syscalls assert bench args flags
```

`args` + `flags` arrived with the CLI. DNS (0.4.0) and IPv6 (0.5.x) added none — the
resolver and the v6 framing are built directly on `platform_*` and stay in-tree.
`cyrius deps` vendors these into the gitignored `lib/`, hash-locked in `cyrius.lock`
(27 files at the 6.5.35 pin).

**taar** (`cyrius.cyml [deps.taar]`) — **0.5.0**, `modules = ["dist/taar.cyr"]`.
`path = "../taar"` resolves local dev; `git` + `tag` is the published fallback. yo
consumes **one symbol**, `ipv4_parse`; the bundle's `socket`/`dns` modules ride along
and DCE out. The 0.6.x plan below is **done** — the extraction landed at 0.5.5.

## Family (all three consumers now real)

The substrate and both siblings exist; none of this is "planned" any more.

| Repo | Version | Cyrius pin | taar | Relationship |
|---|---|---|---|---|
| **taar** | 0.5.0 | 6.5.35 | — | Substrate. yo folded `src/ipv4.cyr` onto it at 0.5.5. |
| **dig** | 0.3.5 | 6.2.24 | 0.3.1 | DNS resolver. Second `ipv4` consumer — it forced the extraction. |
| **whirl** | 0.6.4 | 6.4.25 | 0.3.1 | curl/wget. Third consumer; uses taar's `socket` + `dns`, which yo does not. |

**Family drift**: as of 2026-08-26 yo is the *first* of the three to reach 6.5.35 and
taar 0.5.0 — `dig` and `whirl` still pin 6.2.24 / 6.4.25 and taar 0.3.1. That is fine
(taar's `ipv4_*` surface is stable across 0.3.1 → 0.5.0), but it means yo is the
canary: the migration evidence gathered here — zero stdlib removals or arity changes
across 6.2.24 → 6.5.35 for these 11 modules — applies to them too when they follow.
`whirl` carries the larger risk, since it pulls the crypto/TLS leaves yo does not.

## Kernel coupling (AGNOS backend only)

The AGNOS backend (future `src/platform_agnos.cyr`) will depend on a Cyrius-native ICMP primitive reachable from ring-3. The ICMP *logic* already exists in-kernel — `icmp_ping(dst_ip) → rtt_ticks` + `net_handle_icmp` in `agnos/kernel/core/net_icmp.cyr` (split from `net.cyr` in the 1.36.x refactor) — but it has only in-kernel callers (`selftests.cyr`, in-kernel `shell.cyr`); **agnos must still expose it (plus UDP + ifindex) as syscalls in its sovereign ABI** before a ring-3 `yo` can call it. The Linux backend has no AGNOS kernel coupling — it uses POSIX socket() against the host kernel directly.

Now that the Linux backend exists, we have a concrete reference for what shape the AGNOS surface needs. The Linux call sites in `src/probe.cyr` and `src/dns.cyr` use:

- `platform_icmp_open()` → fd (or sovereign handle). On Linux, also enables `IP_RECVTTL` so recv carries the response TTL.
- `platform_icmp_send_to(fd, packed_addr, pkt, pkt_len)` → bytes_sent
- `platform_icmp_recv_ext(fd, buf, maxlen, ttl_out)` → bytes_received, also writes response TTL to `*ttl_out` (0 if unavailable). With SO_RCVTIMEO equivalent for the timeout. *(0.4.3: TTL)*
- `platform_icmp6_open()` → fd. On Linux, also enables `IPV6_CHECKSUM=2` (kernel fills outbound cksum) and `IPV6_RECVHOPLIMIT`. *(0.5.0: IPv6)*
- `platform_icmp6_send_to(fd, addr16_ptr, scope_id, pkt, pkt_len)` → bytes_sent; addr16 is the packed 16-byte network-order destination. *scope_id is the ifindex for link-local destinations (0 for global / loopback).* *(0.5.2: scope ID)*
- `platform_icmp6_recv_ext(fd, buf, maxlen, hop_out)` → bytes_received + writes hop limit (0..255) to `*hop_out` from the IPv6 cmsg chain.
- `platform_resolve_ifindex(name)` → ifindex (≥1) or 0. On Linux, reads `/sys/class/net/<name>/ifindex`. Used by the literal-v6 dispatch to translate `%zone` into a sockaddr scope_id. *(0.5.2: scope ID)*
- `platform_udp_open()` → fd
- `platform_udp_send_to(fd, packed_addr, port, pkt, pkt_len)` → bytes_sent  *(0.4.0: DNS)*
- `platform_udp_recv(fd, buf, maxlen)` → bytes_received
- `platform_read_file(path, buf, maxlen)` → bytes_read  *(0.4.0: /etc/resolv.conf)*
- `platform_set_recv_timeout_ms(fd, ms)`
- `platform_now_us()` and `platform_sleep_ms(ms)`

The AGNOS shape can match this 1:1, OR the kernel can offer the more focused `icmp_echo(addr, timeout_ms) → rtt_us`. **The kernel has already de-facto chosen the focused form** — `icmp_ping(dst_ip)` returns elapsed timer_ticks and internally does the send + bounded `net_poll` wait — so when it's surfaced as a syscall `platform_agnos.cyr` will collapse `_send_to + _recv` into that one call. Per [[project_agnos_kernel_growth_rules]], the final ABI shape is decided when AGNOS opens the cycle; the Linux reference doesn't dictate it. The UDP surface will need an equivalent sovereign primitive for the AGNOS-side `dns_resolve` (likely `net_udp_send_recv` with a per-process port-binding table similar to `net.cyr:142-196`).

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| Ring-3 ICMP/UDP/ifindex syscalls | promoting existing `icmp_ping` + net primitives into the agnos sovereign ABI | agnos |
| `taar` substrate extraction | Second consumer (`whirl` or `dig`) arriving | yo + sibling repos |
| LAN-on-iron validation | the two gates above + `src/platform_agnos.cyr` (iron RX already proven) | agnos + yo |
| QEMU + localhost validation | ring-3 ICMP syscall + `src/platform_agnos.cyr` | agnos + yo |

## Consumers

None yet. yo IS a leaf consumer of the kernel; nothing depends on yo today.

## Cross-references

- [`roadmap.md`](roadmap.md) — milestone plan through v1.0
- `cyrius/lib/args.cyr:99` + `cyrius/lib/args_agnos.cyr` + `cyrius/lib/syscalls_x86_64_agnos.cyr` — the agnos userland stdlib surface (the old gate #1 lived in args.cyr and is now closed; `syscalls_x86_64_agnos.cyr:1190` also now offers `sys_net_dns_server()`, which supersedes yo's interim raw `syscall(61, 3)` at `src/platform_agnos.cyr:134`)
- `agnos/kernel/core/net_icmp.cyr` (`icmp_ping`) + `agnos/kernel/core/syscall.cyr` — the kernel ICMP logic + where gate #2 (ring-3 syscall) lands
- [agnosticos shared-crates.md § yo + taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — substrate plan

> **Doc hygiene note (updated 2026-08-26):** the AGNOS-blocker status above is verified against live cyrius + agnos *source*, NOT sibling-repo state.md prose (which lags). The 2026-08-26 pass caught this file's *own* prose lagging the same way: gate #1 had been closed in `cyrius/lib/args.cyr` for several releases while two refreshes here kept restating it as open. Re-check the code — including the claims in this file — not the prose.
