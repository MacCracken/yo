# yo — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-05-23 (0.5.1 cut — AAAA / ip6.arpa / -4-6).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.5.1** — AAAA + ip6.arpa + `-4`/`-6` (second 0.5.x item) |
| Status | **Linux MVP at POSIX-ping output parity for v4 + v6, literals + hostnames** — `yo dns.google` (A default), `yo -6 dns.google` (AAAA), `yo ::1` (ip6.arpa PTR → `(localhost)`), `yo <ula>` (ip6.arpa PTR → `(archaemenid)`). AGNOS backend pending kernel surface. Scope IDs + IPv4-embedded textual form still deferred to 0.5.2. |
| Build size | ~96 KB (Linux MVP + v4/v6 DNS forward+reverse + multi-target + TTL/hoplimit + canonical v6 banner, pre-DCE; 288 unreachable fns in main, ~310 in tests) |
| Cyrius pin | 6.0.1 |
| Tests | 298 assertions in `tests/yo.tcyr` — ICMP/ICMPv6 framing + CLI parse (incl. `-4`/`-6` + conflict) + IPv4/IPv6 parsers + RTT stats + output format (v4 + v6 RFC 5952 canonical) + DNS forward (A, AAAA) + reverse (in-addr.arpa, ip6.arpa) + cmsg TTL/hop-limit walker |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | First entry in network-tools family |
| Backends | Linux (working) · AGNOS (planned) · Windows/Apple (post-1.0) |

## In-flight work

**0.5.1 IPv6 polish landed** — AAAA DNS lookup, `ip6.arpa` PTR reverse-DNS, `-4` / `-6` family-forcing flags, RFC 5952 canonical v6 banner formatter. `yo dns.google` defaults to A (POSIX expectation); `yo -6 dns.google` resolves AAAA and banners `dns.google (2001:4860:4860::8844)` even though probing then times out for lack of global v6 route. `yo ::1` banners `::1 (localhost)` via ip6.arpa. Modules touched in 0.5.1:

- `src/dns.cyr` — `DNS_TYPE_AAAA=28`. `_dns_build_query` takes a `qtype` arg. New `dns_resolve_aaaa`, `_dns_parse_aaaa_response`, `_dns_build_reverse_qname_v6` (32 nibble labels + `ip6.arpa.`), `_dns_build_ptr_query_v6`, `dns_reverse_resolve_v6`, `_dns_nibble_to_hex`.
- `src/cli.cyr` — `-4`/`--ipv4` and `-6`/`--ipv6` bool flags; registry 72 B → 88 B; new `CLI_ERR_AF_CONFLICT`.
- `src/main.cyr` — dispatch is now `ipv4_parse` → `ipv6_parse` → `dns_resolve(A)` → `dns_resolve_aaaa`, restricted by `-4`/`-6`. v6 reverse DNS hooked in. AAAA banner uses the canonical formatter.
- `src/output.cyr` — `output_ipv6_to_buf` (RFC 5952), helpers `_output_nibble_to_buf` / `_output_u16_hex_to_buf`.
- `tests/yo.tcyr` — 46 new assertions (298 total) across CLI `-4`/`-6`, v6 reverse qname, AAAA parser, v6 canonical banner.

**Iron-verified**: see 0.5.1 CHANGELOG entry for the full smoke matrix. Global IPv6 still unreachable from archaemenid (no `2000::/3` route — also confirmed by system `ping -6`).

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

**0.5.x band substantially complete with 0.5.1** — POSIX-ping output parity for v4 + v6, both literals and hostnames, both directions of DNS, with `-4`/`-6` family forcing. Remaining 0.5.x tail items (scope IDs, IPv4-embedded textual form) can land as 0.5.2 when needed, but they don't block the AGNOS work. Next milestone: **0.6.x AGNOS backend** — needs a sovereign equivalent of `platform_icmp_recv_ext` / `platform_icmp6_recv_ext` (cmsg-or-equivalent surface for TTL/hop-limit) and sovereign UDP for the DNS path. Blocked on agnos kernel ICMP surface (r8169 RX-path 5-part bundle iron-validating, Attempt 97 pending). See [`roadmap.md`](roadmap.md) for the full path to 1.0.

Pending later:
- **AGNOS backend** (`src/platform_agnos.cyr`) — pending the kernel ICMP surface in agnos (blocked on r8169 RX-path 5-part bundle iron-validating, Attempt 97 pending). Slots in as a sibling to `platform_linux.cyr` with no changes to `probe.cyr`. Will also need a sovereign UDP surface for the AGNOS-side `dns_resolve`.
- **`taar` substrate extraction** — waits for `dig` to grow into a real second consumer.

## Dependencies (current — `cyrius.cyml [deps].stdlib`)

```
string fmt alloc io vec str syscalls assert bench args flags
```

`args` + `flags` added when CLI landed. 0.4.0 (DNS) added no stdlib deps — the resolver is built directly on `platform_udp_*` and ipv4_parse, keeping the dep list lean. Will grow further:

- **0.5.x**: IPv6 framing helpers — likely no new stdlib needs, all in-tree.
- **0.6.x**: `taar` extraction moves network primitives OUT of `yo`'s vendored stdlib INTO a sibling repo. `cyrius.cyml [deps]` gains `taar = { path = "../taar" }` or registry equivalent.

## Sibling repos (planned, not yet scaffolded)

- **whirl** — curl / wget equivalent. Triggers `taar` extraction when it arrives.
- **dig** — DNS resolver. Also triggers `taar` extraction if it arrives first.
- **taar** — substrate library (network-probe primitives). Per [[project_tools_stable_ideas]] memory: real lib from cycle open given three named consumers in the brainstorm window.

## Kernel coupling (AGNOS backend only)

The AGNOS backend (future `src/platform_agnos.cyr`) will depend on a Cyrius-native ICMP primitive in `agnos/kernel/core/net.cyr`. The Linux backend has no AGNOS kernel coupling — it uses POSIX socket() against the host kernel directly.

Now that the Linux backend exists, we have a concrete reference for what shape the AGNOS surface needs. The Linux call sites in `src/probe.cyr` and `src/dns.cyr` use:

- `platform_icmp_open()` → fd (or sovereign handle). On Linux, also enables `IP_RECVTTL` so recv carries the response TTL.
- `platform_icmp_send_to(fd, packed_addr, pkt, pkt_len)` → bytes_sent
- `platform_icmp_recv_ext(fd, buf, maxlen, ttl_out)` → bytes_received, also writes response TTL to `*ttl_out` (0 if unavailable). With SO_RCVTIMEO equivalent for the timeout. *(0.4.3: TTL)*
- `platform_icmp6_open()` → fd. On Linux, also enables `IPV6_CHECKSUM=2` (kernel fills outbound cksum) and `IPV6_RECVHOPLIMIT`. *(0.5.0: IPv6)*
- `platform_icmp6_send_to(fd, addr16_ptr, pkt, pkt_len)` → bytes_sent; addr16 is the packed 16-byte network-order destination.
- `platform_icmp6_recv_ext(fd, buf, maxlen, hop_out)` → bytes_received + writes hop limit (0..255) to `*hop_out` from the IPv6 cmsg chain.
- `platform_udp_open()` → fd
- `platform_udp_send_to(fd, packed_addr, port, pkt, pkt_len)` → bytes_sent  *(0.4.0: DNS)*
- `platform_udp_recv(fd, buf, maxlen)` → bytes_received
- `platform_read_file(path, buf, maxlen)` → bytes_read  *(0.4.0: /etc/resolv.conf)*
- `platform_set_recv_timeout_ms(fd, ms)`
- `platform_now_us()` and `platform_sleep_ms(ms)`

The AGNOS shape can match this 1:1, OR the kernel can offer the more focused `icmp_echo(addr, timeout_ms) → rtt_us` — at which point platform_agnos.cyr collapses `_send_to + _recv` into a single call internally. Per [[project_agnos_kernel_growth_rules]], the shape is decided when AGNOS opens the cycle; the Linux reference doesn't dictate it. The UDP surface will need an equivalent sovereign primitive for the AGNOS-side `dns_resolve` (likely `net_udp_send_recv` with a per-process port-binding table similar to `net.cyr:142-196`).

## Carry-forward (dependent on other repos)

| Item | Blocked on | Owning repo |
|---|---|---|
| Kernel ICMP syscall | r8169 RX-path 5-part bundle iron-validating | agnos (Attempt 97 pending) |
| `taar` substrate extraction | Second consumer (`whirl` or `dig`) arriving | yo + sibling repos |
| LAN-on-iron validation | Kernel ICMP + r8169 iron-clear | agnos + yo |
| QEMU + localhost validation | Kernel ICMP loopback path | agnos + yo |

## Consumers

None yet. yo IS a leaf consumer of the kernel; nothing depends on yo today.

## Cross-references

- [`roadmap.md`](roadmap.md) — milestone plan through v1.0
- [agnosticos r8169-rx-path-audit.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/r8169-rx-path-audit.md) — the iron dependency
- [agnosticos shared-crates.md § yo + taar](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md) — substrate plan
