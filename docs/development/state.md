# yo — Current State

> **⚠ NOT A LOG.** Live state with pointers — current truth only. Per-release history → [`../../CHANGELOG.md`](../../CHANGELOG.md). Milestone path → [`roadmap.md`](roadmap.md).
>
> **Last refresh**: 2026-05-23 (scaffold cut).

---

## Snapshot

| Field | Value |
|---|---|
| Current version | **0.1.0** (scaffold) |
| Status | Pre-MVP — kernel ICMP syscall surface pending |
| Build size | ~68 KB (CLI + ICMP framing, pre-DCE) |
| Cyrius pin | 6.0.1 |
| Tests | 36 assertions in `tests/yo.tcyr` covering ICMP framing + RFC 1071 checksum + CLI parse |
| Iron-validation host | archaemenid (Beelink SER, AMD) — same machine as the agnosticos iron-burn surface |
| Family position | First entry in network-tools family |

## In-flight work

- **ICMP framing module landed** (`src/icmp.cyr`, unreleased): RFC 792 echo packet builder + RFC 1071 checksum + verify. Pure code, fully unit-tested. Models the checksum on `agnos/kernel/core/net.cyr:25` so kernel-side recv-path verification stays byte-identical.
- **CLI surface landed** (`src/cli.cyr` + `src/main.cyr`, unreleased): full flag inventory per roadmap 0.3.x (`-c -W -i -s -q -v -h` + long forms) wired through `lib/flags.cyr`. `yo <host>` parses cleanly and prints a planned-probe banner; the call site where the kernel ICMP loop will slot is the `_print_planned()` body. yo is the first consumer of `lib/flags.cyr` in the ecosystem.

Still pending: **0.2.x — Kernel ICMP primitive** in agnos (blocked on r8169 RX-path 5-part bundle iron-validating, Attempt 97 pending). When that surface lands, replace the `_print_planned()` placeholder with the real send/recv/verify loop using the already-tested `icmp_*` helpers.

## Dependencies (current — `cyrius.cyml [deps].stdlib`)

```
string fmt alloc io vec str syscalls assert bench args flags
```

`args` + `flags` added when CLI landed. Will grow further:

- **0.3.x (remainder)**: + `net` (kernel network primitives — vendored from `agnos/kernel/core/net.cyr` patterns or via the kernel-syscall surface).
- **0.4.x**: + DNS resolution primitives, IPv6 framing helpers.
- **0.6.x**: `taar` extraction moves network primitives OUT of `yo`'s vendored stdlib INTO a sibling repo. `cyrius.cyml [deps]` gains `taar = { path = "../taar" }` or registry equivalent.

## Sibling repos (planned, not yet scaffolded)

- **whirl** — curl / wget equivalent. Triggers `taar` extraction when it arrives.
- **dig** — DNS resolver. Also triggers `taar` extraction if it arrives first.
- **taar** — substrate library (network-probe primitives). Per [[project_tools_stable_ideas]] memory: real lib from cycle open given three named consumers in the brainstorm window.

## Kernel coupling

`yo` depends on a Cyrius-native ICMP primitive in `agnos/kernel/core/net.cyr` (not POSIX `socket()`). Shape decided when `agnos` opens the cycle that lands the ICMP surface. Two candidate shapes:

- **Focused**: `icmp_echo(addr, timeout_ms) → rtt_us` — single-purpose, lowest kernel surface area.
- **General**: `net_send_raw(payload, len) → handle` + `net_recv_raw(handle, buf, maxlen, timeout) → bytes` — broader surface, shared by `whirl` (HTTP) and `dig` (DNS) too.

Per [[project_agnos_kernel_growth_rules]], the shape is decided by what `yo` ACTUALLY needs, refined when `dig` arrives. Don't pre-design.

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
