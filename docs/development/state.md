# yo — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-05-23 (0.4.0 cut — DNS resolution).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.4.0** — DNS resolution (first 0.4.x item) |
| Status | **Linux MVP + DNS working** — `yo <hostname>` resolves and probes end-to-end. AGNOS backend pending kernel surface. |
| Build size | ~92 KB (Linux MVP + DNS, pre-DCE; 286 unreachable fns) |
| Cyrius pin | 6.0.1 |
| Tests | 133 assertions in `tests/yo.tcyr` covering ICMP framing/checksum + CLI parse + IPv4 parse + RTT stats + output format + DNS qname/query/response/resolv.conf |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | First entry in network-tools family |
| Backends | Linux (working) · AGNOS (planned) · Windows/Apple (post-1.0) |

## In-flight work

**0.4.0 DNS landed** — `yo google.com` → `yo google.com (142.251.214.110) — 56 bytes ...`. Resolver is RFC 1035 A-records only, sends a single UDP query to the first nameserver in `/etc/resolv.conf` (fallback `1.1.1.1`), 2 attempts at 2 s SO_RCVTIMEO. NXDOMAIN exits 2 with `yo: cannot resolve host: <name>`. New modules:

- `src/dns.cyr` — QNAME encoder, query builder, response parser (compressed-pointer NAMEs, skips CNAMEs to the first A record), `/etc/resolv.conf` line parser. Self-contained; uses `platform_udp_*` directly per the per-backend sovereignty rule.
- `src/platform_linux.cyr` — UDP primitives: `platform_udp_open` / `_send_to(fd, addr, port, ...)` / `_recv`, plus `platform_read_file(path, buf, maxlen)` for `/etc/resolv.conf`. `_lx_sockaddr_in` now takes a port arg (network byte order), shared by ICMP (port=0) and UDP send paths.
- `src/output.cyr` — banner now appends `(a.b.c.d)` when target was DNS-resolved.

**0.3.0 carryover** (still the underlying Linux MVP):

- `src/platform.cyr` + `src/platform_linux.cyr` — Linux backend. SOCK_DGRAM ICMP with SOCK_RAW fallback. Raw syscalls (`open=2`, `read=0`, `sendto=44`, `recvfrom=45`, `clock_gettime=228`, `nanosleep=35`, `socket=41`, `close=3`, `setsockopt=54`, `signalfd4=289`).
- `src/probe.cyr` — probe loop. Per-packet send/recv with SO_RCVTIMEO; sleep between iterations; per-packet output + summary; passes `show_resolved` flag through to the banner.
- `src/icmp.cyr` — RFC 792 framing + RFC 1071 checksum. Already wired through the probe loop. Will stay byte-identical for the AGNOS backend.
- `src/cli.cyr` — flag inventory. First consumer of `lib/flags.cyr` in the ecosystem.
- `src/ipv4.cyr` — strict dotted-quad parser. Matches `agnos/kernel/core/net.cyr:21` `ip4()` packing.
- `src/stats.cyr` + `src/output.cyr` — RTT accumulator + README-shaped output.

Next milestones in the **0.4.x band**: reverse DNS lookup (PTR queries — banner gains `(name)` for literal-IP targets), multiple targets (sequential probe runs with combined exit), TTL/hop-limit display (cmsg via `IP_RECVTTL` on SOCK_DGRAM). All Linux-backend work; no platform-layer changes needed. See [`roadmap.md`](roadmap.md) for the full path to 1.0.

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

- `platform_icmp_open()` → fd (or sovereign handle)
- `platform_icmp_send_to(fd, packed_addr, pkt, pkt_len)` → bytes_sent
- `platform_icmp_recv(fd, buf, maxlen)` → bytes_received (with SO_RCVTIMEO equivalent for the timeout)
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
