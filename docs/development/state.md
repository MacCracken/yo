# yo — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-05-23 (0.4.3 cut — TTL display, closes 0.4.x).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.4.3** — TTL display (fourth 0.4.x item; band complete) |
| Status | **Linux MVP at POSIX-ping output parity** — `yo router 8.8.8.8 1.1.1.1` runs sequential per-target probes with TTL on each reply line. AGNOS backend pending kernel surface; next milestone is 0.5.x IPv6. |
| Build size | ~96 KB (Linux MVP + DNS forward+reverse + multi-target + TTL ancillary, pre-DCE; 287 unreachable fns in main, 305 in tests) |
| Cyrius pin | 6.0.1 |
| Tests | 187 assertions in `tests/yo.tcyr` — ICMP framing/checksum + CLI parse (incl. `-n`, multi-target) + IPv4 parse + RTT stats + output format + DNS forward+reverse (qname encoders, query builders, response parsers for A and PTR, name decoder w/ pointer guard, resolv.conf parser) + cmsg TTL walker |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | First entry in network-tools family |
| Backends | Linux (working) · AGNOS (planned) · Windows/Apple (post-1.0) |

## In-flight work

**0.4.3 TTL display landed** — `yo 1.1.1.1` now banners `seq=0  ttl=57  rtt=5.83 ms`. Linux's `IP_RECVTTL` socket option is enabled on the ICMP socket; the recv path switched from `recvfrom` to `recvmsg` (syscall 47) to carry the cmsg chain; a pure helper walks the chain to find `(IPPROTO_IP, IP_TTL)`. When the kernel doesn't surface a TTL cmsg (older kernels / SOCK_RAW edge cases) the ttl chunk is omitted gracefully. Modules touched since 0.4.2:

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

**0.4.x band is now closed.** Next milestone: **0.5.x IPv6** — `src/ipv6.cyr` colon-hex parser, ICMPv6 framing (echo req=128, echo reply=129, pseudo-header checksum), `platform_linux.cyr` gains `AF_INET6` + `sockaddr_in6` builder + `IPPROTO_ICMPV6=58`, CLI gains `-4` / `-6`. AGNOS backend will need an equivalent `platform_icmp_recv_ext`-shaped surface (sovereign cmsg-or-equivalent for TTL/hop-limit), but doesn't block. See [`roadmap.md`](roadmap.md) for the full path to 1.0.

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
