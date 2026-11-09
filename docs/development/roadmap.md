# yo — Roadmap

> **Status**: Active | **Last updated**: 2026-11-08 (unreleased 0.8.x: the AGNOS `-W`, counter and SIGINT items)
>
> The plan from here to v1.0, then the trigger-gated backlog after it. Shipped work
> is not listed: its record is [`CHANGELOG.md`](../../CHANGELOG.md), and the audit
> that closed 0.7.x is [`docs/audit/2026-11-08-audit.md`](../audit/2026-11-08-audit.md).
> Volatile state (versions, sizes, test counts) lives in [`state.md`](state.md).

---

## Where yo stands

Both shipping backends work. Linux covers IPv4 and IPv6 with DNS, reverse DNS,
scope IDs and multiple targets. AGNOS reaches ICMP through the sovereign kernel
surface; it is iron-validated (agnos 1.51.7 burn), and the QEMU smoke passes.
The 0.7.2 P(-1) audit fixed 25 findings. `cyrius audit` is clean and gated in CI,
every new guard is mutation-checked, a fuzz harness covers every byte parser, and
an integration harness runs the binary in a network namespace in CI.

What is left before 1.0 is three bands: backend parity (0.8.x), where the AGNOS
arm has now adopted the kernel surface it was missing (`-W`, ICMP counters,
SIGINT) and Linux still needs aarch64-correct syscalls; Linux portability and
resolver gaps (0.9.x); and a set of behaviour decisions to make before the
surface is frozen (0.10.x).

---

## 0.8.x — backend parity

The AGNOS `-W`, ICMP-counter and SIGINT items shipped (CHANGELOG `[Unreleased]`).
What they could not reach is a kernel property, recorded in `state.md` § Kernel
coupling. agnos raises no signal from the console, so Ctrl-C at the keyboard
reaches no program, and an ordinary signal cannot end a reply wait.

- [ ] **aarch64-correct Linux syscalls.** `src/platform_linux.cyr` still reaches the
      original socket, file, clock and signal paths by x86_64 number (`_LX_SYS_*`).
      On aarch64, 44 is `fstatfs(2)`, not `sendto`, so an `--aarch64` build compiles
      clean and is wrong. Route them through the stdlib `sys_*` wrappers, as the
      0.7.2 code already does, and add a CI leg that *runs* the binary under
      `qemu-aarch64`. taar hit this exact defect at its 0.3.3.
- [ ] **A gateway-literal run on iron** (`yo 192.168.1.1` on an AGNOS-booted box).
      The 1.51.7 burn probed a WAN host by name; the LAN-literal half of the iron
      criterion has no evidence of its own. The same burn should be the first iron
      run of the `icmp_echo_ex`#100 path and the `--diag` counters, which have run
      only in QEMU, and it needs an agnos of at least 1.56.48 to reach them.
- [ ] **AGNOS execution in CI**, if a runner can boot it. The QEMU smoke is a manual
      gate: it needs the agnos, gnoboot and agnoshi checkouts plus QEMU and OVMF. The
      CI `--agnos` build only proves the arm compiles. Decide whether a cached
      kernel image plus `qemu-system-x86_64` on the runner is worth it.

## 0.9.x — Linux completeness: resolver and diagnostics

- [ ] **IPv6 nameservers in `/etc/resolv.conf`.** They are skipped, and since 0.7.2
      a file naming only IPv6 servers fails closed rather than falling back to
      1.1.1.1. That is safe, but on a v6-only network DNS then does not work at
      all. Needs `ipv6_parse` on the resolv.conf path plus a v6 UDP query socket.
- [ ] **ICMP error replies.** Destination-unreachable and time-exceeded replies read
      as timeouts. iputils prints `From <router>: Destination Host Unreachable`, and
      that line is often the whole diagnosis.
- [ ] **Answer owner-name / CNAME-chain validation.** yo takes the first A / AAAA /
      PTR of class IN anywhere in the answer section. glibc checks the owner chain;
      musl does not. Decide how strict, then implement (taar holds the same item).
- [ ] **Release artifacts with checksums and a signature.** `release.yml` uploads
      `build/*` with neither. cyrius's own release pipeline (an Ed25519-signed
      checksum list) is the pattern.
- [ ] **Integer flags that wrap.** `lib/flags.cyr` has no overflow check, so
      `-s 18446744073709551672` parses as 56; yo's range checks only see the
      wrapped value. Fix it upstream in cyrius, or let the cmdit move (below)
      settle it, then add the test.
- [ ] **Adopt cmdit** if the CLI surface work in 0.10.x wants it. See § Appendix:
      adopting cmdit.

## 0.10.x — behaviour decisions, then the surface freeze

The audit deferred these because each is a choice about what yo *should* do, not
a defect. Decide each, implement the decision, then freeze the CLI and output
format as the 1.0 contract.

- [ ] **Loss percentage.** It truncates, so 1 lost out of 101 prints `0% loss`, and
      a script grepping for `0% loss` gets a false pass. Options: one decimal place,
      or round any loss up to at least 1%.
- [ ] **`-c 0` and continuous mode.** `-c 0` sends nothing and exits 1. iputils
      runs until Ctrl-C by default. yo's default is 4.
- [ ] **`-W` / `-i` units.** They are milliseconds, where iputils uses seconds
      (with fractions). Keep milliseconds and document it loudly, or accept
      iputils' form.
- [ ] **Interval semantics.** `-i` is the delay after the reply wait, so a lost probe
      costs `-W` + `-i` (2 s at the defaults; iputils takes 1 s). The alternative
      is send-to-send pacing.
- [ ] **Minimum interval for unprivileged users.** iputils requires root below 2 ms.
      yo allows `-i 0` for anyone, bounded only by RTT or `-W`.
- [ ] **Exit-code aggregation across targets.** Any reply on any target exits 0, even
      if another target failed to resolve.
- [ ] **`-v` / `--verbose`.** Parsed, and nothing reads it. Implement it (per-packet
      ident, checksum, payload length?) or remove it.
- [ ] **Reply source-address filtering.** yo does not compare a reply's source with
      the target, and iputils does not either. Filtering would harden the SOCK_RAW
      path against spoofing, but break pinging 0.0.0.0 and multicast. Since 0.7.2
      the random per-process ident already ends cross-talk.
- [ ] **SIGTERM on AGNOS.** agnos gives SIGTERM no default action, so `kill 15`
      does nothing to yo there; on Linux it ends yo (without a summary). Watch
      SIGTERM beside SIGINT on AGNOS, so a supervisor's polite stop works, or
      leave it to the supervisor's SIGKILL.
- [ ] **The missing-resolv.conf default.** yo falls back to 1.1.1.1; glibc and musl
      use 127.0.0.1. taar holds the same decision open.
- [ ] **Release build flags.** `CYRIUS_DCE=1` now strips dead code: 86,248 B
      against 200,936 B for the default build. Decide whether releases ship the DCE
      build, which settles the size criterion below.
- [ ] **Freeze.** Write the CLI flags, output lines, exit codes and `--diag` keys
      down as the 1.0 contract (a `docs/` page that tests are held to), then run the
      pre-freeze P(-1) the first-party standard requires.

---

## v1.0 criteria (release gate)

Ship 1.0 when all of these are true.

- [x] **Feature parity with POSIX `ping` on Linux**: `-c -W -i -s -q -v`, IPv4 +
      IPv6, DNS and reverse DNS, multiple targets, TTL. Plus `-n`, `-4` / `-6` and
      `--diag`. (`-f`, `-D`, `-I`, `-M` are v1 backlog.)
- [x] **AGNOS backend working end to end**: the QEMU smoke passes, and iron
      validation passed (agnos 1.51.7 burn).
- [x] **No POSIX `socket()` and no raw syscall numbers in the AGNOS backend** (ADR 0001).
- [x] **Test gates that mean something**: unit assertions with mutation-checked
      guards, a fuzz harness over every parser (also under `--poison`), and the
      namespace integration harness, all in CI.
- [ ] **0.8.x done**: Linux is aarch64-correct and run under `qemu-aarch64` in CI,
      and a gateway-literal iron run is recorded. (AGNOS `-W`, ICMP counters and
      SIGINT are done; console Ctrl-C does not exist on agnos and is not a yo item.)
- [ ] **0.10.x decisions made and the surface frozen.**
- [ ] **Binary size**: no larger than the system `ping` (iputils 155,160 B). The old
      "≤ 30 KB after DCE" was an unmeasured guess and is withdrawn. Today's default
      build (200,936 B) fails this; the DCE build (86,248 B) passes.
- [ ] **Wall clock**: at or under iputils' per-invocation time. 0.6.0 measured yo at
      381 µs against 458 µs; re-measure on the freeze candidate.
- [ ] **A P(-1) pass on the freeze candidate**, filed in `docs/audit/`.
- [ ] **CI green on the candidate**, including the integration harness on GitHub's
      runners (its `sudo unshare` branch first ran at 0.7.2).

---

## v1 backlog (post-1.0)

Each waits on the trigger named; none is scheduled.

| Item | Trigger |
| --- | --- |
| Flood mode (`-f`) | a stress-test need; needs the 0.10.x unprivileged-interval decision first |
| Per-packet timestamps (`-D`) | log-aggregator piping demand |
| Bind a source interface or address (`-I`) | multi-homed hosts asking |
| Path-MTU probe (`-M do`, DF set) | tunnel / VPN MTU diagnosis demand |
| JSON output (`--json`) | a consumer (sutra, aegis, phylax) that reads it |
| Audit-chain logging | `libro` shipping a consumer API |
| IPv6 on AGNOS (`yo -6`) | agnos growing an IPv6 subsystem. NDP *is* ICMPv6, so this is a kernel subsystem, not a syscall ask; filed in agnos's roadmap § OPEN |
| `%zone` scope IDs on AGNOS | link-local IPv6 on agnos (subsumed by the item above) |
| Windows backend (`IcmpSendEcho`) | cyrius Windows targets at parity |
| Apple backend (macOS DGRAM ICMP) | cyrius macOS targets at parity |

## Out of scope

- **Privilege model.** On AGNOS a raw send will need a `kavach` capability; on Linux
  yo works through `ping_group_range` or CAP_NET_RAW. Capability gating belongs to
  aegis / kavach, not yo.
- **A multi-host load harness.** That is a `whirl --bench`-class concern.
- **TUI / GUI.** yo is CLI-only.

---

## Appendix: adopting cmdit (CLI parsing)

**Demand-gated, not a forced sweep.** The 2026-06-25 ecosystem CLI review
([agnosticos `planning/cmdit.md`](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/cmdit.md))
lists yo as a Tier-1 drop-in. This was read against cmdit 1.2.6 / 1.3.1 source on
2026-10-14 and refreshed for yo 0.7.2. cmdit is at **1.5.1** (cyrius 6.7.18) as of
2026-11-08, so re-read its README at the tag you adopt. yo parses with stdlib
`flags`, so this is the kii/anuenue re-fold rather than a rewrite.

**Site → cmdit:**

- [ ] `cli_new`: `flags_new()` → `cmdit_new("yo")`, and drop the `-h` registration
  and its slot (cmdit owns `-h/--help`). `flags_add_int` → `cmdit_int`;
  `flags_add_bool(fs,c,l,0,h)` → `cmdit_bool(fs,c,l,h)`.
- [ ] Keep `cli_parse_argv(reg, argc, argv)` as the pure test seam, calling
  `cmdit_parse_argv`. `main` does `n = cmdit_argv(h)` and then
  `cli_parse_argv(reg, n, cmdit_raw_argv(h))`; delete `_materialize_argv`. yo has
  no env or required flags, so no `cmdit_finalize`.
- [ ] Map `CMDIT_HELP` → `CLI_HELP` and `CMDIT_RESULT_ERR` → `CLI_ERR_PARSE`. Missing
  host → `cmdit_require_positionals(h, 1)`, after the AF check, to keep today's order.
  Keep yo's own error lines.
- [ ] Keep the post-parse checks: the `< 0` checks, the 0.7.2 upper bounds and
  `-W >= 1` (`CLI_ERR_RANGE`). `cmdit_range` rejects inside the parse loop, so
  `yo -h -c -3` would become an error where it prints help today. The `-4`/`-6`
  mutex stays caller-side.
- [ ] Help: since 0.7.2 yo prints its own rows on **stdout** (`_cli_help_row`), because
  `flags_print_help` writes to stderr. Use `cmdit_help_flags` only if it writes to
  stdout, or keep yo's rows.
- [ ] **Decide the new surface.** cmdit auto-registers `-V/--version`; it does not clash
  with `-v`, and iputils `ping -V` is version too. yo has no version string in `src/`,
  so add one mirroring `VERSION` (whirl's `src/version.cyr` pattern).
- [ ] Check whether cmdit rejects an integer that overflows (0.9.x "integer flags that
  wrap"); if it does, adopting it closes that item.

**`cyrius.cyml`:** drop `"flags"` from `[deps] stdlib` (`src/cli.cyr` is its only
user), keep `"args"` and `"io"`, and add `[deps.cmdit]` with `git`, the adopted
`tag` and `modules = ["dist/cmdit.cyr"]`.

**Tests that move:** the `cli …` groups in `tests/yo.tcyr` drive `cli_parse_argv`
through `_mk_argv` and keep working while the `CliResult` wrapper stays. The
`CLI_REG_SIZE == 96` assertion changes when the help slot goes. `CLI_HELP` is 1,
but `CMDIT_HELP` is 2.

**Output-identity bar:** stdout, stderr and exit code are byte-identical for a bare
host, every flag in short and long form, the error paths, and multi-target runs.
The intended `--help` diffs are cmdit's auto rows. Since cmdit 1.3.1 two more
diffs are intended: a bool given `=value` (`yo --verbose=0`) becomes an error, and
positionals past 128 are kept. Then run `scripts/agnos-qemu-smoke.sh` for the
AGNOS argv path.

---

## Cross-references

- [ADR 0001](../adr/0001-per-backend-sovereignty.md) — why the sovereignty rule is per backend.
- [ADR 0002](../adr/0002-focused-kernel-icmp-syscall.md) — why `icmp_echo`#55 is one-shot, and what that costs.
- [Architecture note 001](../architecture/001-reply-acceptance-invariants.md) — what yo checks before believing a reply.
- [The 0.7.2 audit](../audit/2026-11-08-audit.md) — findings, method, and the deferred items above.
- **Substrate**: [taar](https://github.com/MacCracken/taar); yo consumes one symbol, `ipv4_parse`.
- **Family**: `dig` (DNS) and `whirl` (curl/wget) share taar. Versions and drift are in [`state.md`](state.md).
- **Verify against source, not prose**: agnos's and cyrius's own state docs have lagged their code before. Read the kernel and the stdlib.
