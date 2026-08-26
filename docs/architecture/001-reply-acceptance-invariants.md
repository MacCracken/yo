# 001 — Reply-acceptance invariants

**What this records:** what yo actually checks before it will believe an ICMP
frame is the reply to the probe it just sent — and, just as importantly, what it
deliberately does not check. The answer is different on each of the five reply
paths, because on three of them the *kernel* has already done the filtering and
on two of them nobody has.

As of 0.6.0 yo tests **type** always, **seq** always, and **ident** only on the
SOCK_RAW fallback. It never verifies the received checksum, even though
`src/icmp.cyr` defines `icmp_verify()` and the suite exercises it.

> **This note began as a bug report.** Writing it surfaced a defect that had
> shipped since 0.3.0: the IPv4 `SOCK_RAW` fallback accepted *nothing*, reporting
> 100% loss against hosts that were answering. That is fixed in 0.6.0. The
> analysis is kept in full — see § The weakest link and § How it was fixed —
> because the reasoning is what keeps it from coming back.

Measured on Linux 7.1.9-arch1-2, yo 0.6.0 (cyrius 6.5.35). Every claim below is
either a file:line or a command reproduced at the bottom.

---

## The whole check

`src/probe.cyr:99-146` is the acceptance branch. Stripped of the output calls:

```
var expected_reply = ICMP_ECHO_REPLY;                      # probe.cyr:99
if (af == 6) { expected_reply = ICMPV6_ECHO_REPLY; }
var deadline_us = t0 + timeout_ms * 1000;                  # probe.cyr:101
while (scanning == 1) {                                    # probe.cyr:106
    n = ...recv_ext...;
    if (n < ICMP_HEADER_LEN) { scanning = 0; }             # probe.cyr:111  size floor
    if (scanning == 1) {
        if (icmp_type(rxbuf) == expected_reply) {          # probe.cyr:113
            var is_ours = 1;
            if (icmp_seq(rxbuf) != seq) { is_ours = 0; }   # probe.cyr:121  always
            if (platform_icmp_raw_mode() == 1) {           # probe.cyr:125  RAW only
                if (icmp_ident(rxbuf) != ident) { is_ours = 0; }
            }
            if (is_ours == 1) { got = 1; scanning = 0; }
        }
        if (scanning == 1) {
            if (t1 >= deadline_us) { scanning = 0; }       # probe.cyr:135
        }
    }
}
```

Three accessors from `src/icmp.cyr` reach the probe path, and no more:

```
$ grep -rn "icmp_ident\|icmp_seq\|icmp_cksum\|icmp_type\|icmp_code" src/ | grep -v "^src/icmp.cyr"
src/probe.cyr:113:                    if (icmp_type(rxbuf) == expected_reply) {
src/probe.cyr:121:                        if (icmp_seq(rxbuf) != seq) { is_ours = 0; }
src/probe.cyr:126:                            if (icmp_ident(rxbuf) != ident) { is_ours = 0; }
```

`icmp_cksum` and `icmp_code` are never called outside the test suite. So is
`icmp_verify` — see § `icmp_verify` is test-only for why that is a choice.

Two structural facts shape the rest of this note:

1. **The loop is strictly lock-step.** One `send_to` (`probe.cyr:80`), then reads
   until a match or the deadline, then `seq = seq + 1`. There is never more than
   one probe outstanding, so there is no in-flight *set* to demultiplex against —
   the only question is whether a given frame belongs to the current probe.
2. **The read is bounded by a deadline, not by one syscall.** `SO_RCVTIMEO`
   (`platform_linux.cyr:118`) bounds each individual `recvmsg`, but the loop is
   bounded by `t0 + timeout_ms * 1000`, so a frame that is not ours is skipped
   rather than costing the probe its whole `-W` window. **Before 0.6.0 there was
   no re-read**, and that is half of what made the RAW path fail.

## Why ident matching would fail on SOCK_DGRAM, not merely be unnecessary

`src/probe.cyr:58-61` sets `ident = 0x1234` and says why it does not match on it:

```
# Ident is arbitrary on SOCK_DGRAM (kernel rewrites it with the
# socket-table-managed ID). We still set something deterministic
# in case the SOCK_RAW fallback is in play, where ident is ours.
```

That is exactly right, and it is measurable. Sending ident `0x1234` on an
unprivileged `AF_INET SOCK_DGRAM IPPROTO_ICMP` socket whose auto-bound source
port is 26650:

```
SENT   ident=0x1234 seq=42 cksum=0xee8e
sport after send = 26650
RECV   n=64 type=0 ident=0x681a seq=42 cksum=0xa0a8
```

`0x681a` = 26650 = the socket's source port. The Linux ping-socket path
overwrites the ident field with the socket-table id on send and demultiplexes
inbound replies back to the owning socket by that same id. Three consequences:

- Matching on the ident yo wrote would reject **every** reply. The check is not
  omitted for brevity; adding it naively would break the DGRAM path outright.
- The kernel has already done the filtering yo would be duplicating. A reply
  reaching this socket is, by construction, a reply to this socket's request.
- The checksum is kernel-owned too. Sent `0xee8e`, received `0xa0a8` — the
  kernel recomputed after rewriting the ident, so yo's `icmp_build_echo_request`
  checksum (`icmp.cyr:54-57`) never reaches the wire on this path.

The sequence number survives untouched (`seq=42` out, `seq=42` back). Seq is
therefore matchable on **every** path, which is why 0.6.0 matches it
unconditionally (`probe.cyr:121`) while gating the ident comparison behind
`platform_icmp_raw_mode()` (`probe.cyr:125`) — see § How it was fixed.

The same rewrite happens on IPv6. `::1`, ident `0x1234` out, source port 26652:

```
RECV n=64 type=129 ident=0x681c seq=7
```

`0x681c` = 26652.

## Why checksum verification is redundant — per backend

**IPv6.** `src/icmp.cyr:81-85` states the invariant:

```
# Under Linux AF_INET6 SOCK_DGRAM IPPROTO_ICMPV6, the kernel computes
# and fills the checksum for us when IPV6_CHECKSUM is enabled with the
# offset of the cksum field (=2). On send we leave bytes 2-3 at zero;
# on receive the kernel has already validated the checksum, so we only
# need to verify type == ICMPV6_ECHO_REPLY.
```

The conclusion holds. The stated mechanism does not, and this is the awkward
part worth recording: **`_lx_enable_ipv6_checksum` fails on both v6 sockets and
nobody notices.**

| socket | `setsockopt(IPPROTO_IPV6, IPV6_CHECKSUM, 2)` |
|---|---|
| `AF_INET6 SOCK_DGRAM ICMPV6` | `-92 ENOPROTOOPT` |
| `AF_INET6 SOCK_RAW ICMPV6` | `-22 EINVAL` |

Both call sites (`platform_linux.cyr:341`, `:287`) discard the return value, and
`platform_icmp6_open` reports success regardless. The v6 path works anyway —
`yo -c 2 ::1` returns `2 sent · 2 received · 0% loss` — because Linux computes
and validates the ICMPv6 checksum unconditionally on these sockets; the option
is rejected precisely *because* it is not optional there. So the redundancy
claim survives, but it rests on kernel-mandated behaviour, not on a socket
option yo successfully set. The comment at `icmp.cyr:81-85` and the one at
`platform_linux.cyr:274-277` ("enables IPV6_CHECKSUM") both overstate yo's part.

`IPV6_RECVHOPLIMIT` (`platform_linux.cyr:331`) *does* succeed — which is why
`ttl=64` renders on v6 replies.

**IPv4 SOCK_DGRAM.** The kernel validates the ICMP checksum in `icmp_rcv` before
the frame is ever handed to a ping socket. A yo-side `icmp_verify` would be a
second check of a frame that could not have arrived without passing the first.
Measured indirectly: the received frame above folds to zero under
`icmp_checksum`, i.e. `icmp_verify` would return 1 — it just would not be telling
us anything the kernel had not already enforced.

**AGNOS.** Verification here would be circular. `src/platform_agnos.cyr:59-74`
(`_ag_icmp_pong`) is the model bridge: `sys_icmp_echo(#55)` is one-shot and
returns only an RTT, so `recv_ext` manufactures the reply from the request that
`platform_icmp_send_to` stored at `:47-53` —

```
store8(buf, ICMP_ECHO_REPLY);              # type 8 -> 0        (:67)
store8(buf + 2, 0); store8(buf + 3, 0);    # zero cksum         (:68)
var ck = icmp_checksum(buf, n);            # yo's RFC 1071 checksum (:69)
```

The checksum on that "reply" is one yo computed, in yo's own arithmetic, two
lines earlier. `icmp_verify` on it tests `icmp_checksum` against itself and can
only ever return 1. It would prove nothing about the network. The bytes never
crossed a wire in that form — the real network exchange happened inside the
kernel's `icmp_ping`, and all that came back across the ring-3 boundary was an
integer.

## The five paths

| path | ident yo wrote | IP header on rx | who filters | acceptance |
|---|---|---|---|---|
| Linux v4 `SOCK_DGRAM` | overwritten with sport | absent (n=64) | kernel, by socket id | correct |
| Linux v4 `SOCK_RAW` | **preserved** (`0x1234`) | **present (20 B, n=84)** | yo, since 0.6.0 | correct |
| Linux v6 `SOCK_DGRAM` | overwritten with sport | absent (n=64) | kernel, by socket id | correct |
| Linux v6 `SOCK_RAW` | preserved | absent (n=64) | yo, since 0.6.0 | correct |
| AGNOS | preserved (yo's own bytes) | n/a — synthesised | n/a | correct, and tautological |

## The weakest link was worse than cross-talk — FIXED in 0.6.0

> **Status: fixed.** This section records a real defect that shipped from 0.3.0
> through 0.5.11 and was found while writing this note. It is kept in the past
> tense rather than deleted, because the reasoning is what stops it recurring.
> The fix is in § How it was fixed.

The prior assumption was that the `SOCK_RAW` fallback risks accepting a
concurrently-running pinger's reply. On IPv6 that was exactly the risk. On
**IPv4 it was not a risk, it was a defect**: the RAW path accepted nothing at all.

`raw(7)`: for `AF_INET SOCK_RAW`, the IPv4 header is always included in received
packets. So `rxbuf[0]` is the version/IHL byte, not the ICMP type.
`icmp_type(rxbuf)` (`icmp.cyr:61` — `load8(buf)`) returns `0x45` = 69, which is
never `ICMP_ECHO_REPLY` (0), so the type test in `probe.cyr` (at 0.5.11, the
sole acceptance check) counted every reply as a loss.
Nothing in the repo strips that header — `grep -rn "0x45\|ihl\|IHL" src/` is
empty. The `rxcap` slack comment at `probe.cyr:52-55` shows the question was
considered and answered only for the DGRAM case:

```
# rx buf: ICMP header + max payload + slack for any IP/extension
# bytes the kernel might surface even on SOCK_DGRAM (it doesn't,
# but slack is cheap).
```

Reproduced end-to-end with the shipped binary, forcing the fallback by running
in a user+network namespace whose default `ping_group_range` excludes the caller:

```
$ unshare -r -n -- sh -c 'ip link set lo up; ./build/yo -c 2 --diag 127.0.0.1'
yo 127.0.0.1 — 56 bytes
  seq=0  timeout
  seq=1  timeout
2 sent · 0 received · 100% loss
  --- diag: no reply from 127.0.0.1 (IPv4) ---
  backend         : linux (POSIX socket)
  icmp socket     : SOCK_RAW (privileged fallback)
  ping_group_range: 65534 65534
  last sendto     : ok (packets left the host)
  last recv       : no error recorded
```

Same target, same binary, `SOCK_DGRAM`: `2 sent · 2 received · 0% loss`.

`last recv : no error recorded` is the tell. `_lx_last_recv_err` is only written
on a negative return (`platform_linux.cyr:245`), so it staying 0 means `recvmsg`
returned a frame — the packets came back and were then rejected by the type
check. `--diag` reports this honestly and still misleads: every line is true, and
the block reads as a network problem when it is a parsing problem.

**Is it a real risk?** Yes, in a narrow but reachable band. Reaching the RAW
fallback requires `CAP_NET_RAW` *and* exclusion from `ping_group_range` — root
on a stock Debian/Ubuntu (`ping_group_range` = `0 0`) has gid 0 *inside* that
range and gets `SOCK_DGRAM`, so the common case is safe. The band that is not:
root inside a fresh network namespace or container, where the default is
`65534 65534` (measured above), and any `setcap cap_net_raw+ep` deployment run
by a user outside the range. In that band yo reports 100% loss against a host
that is answering.

Unproven either way: whether the v4 RAW path has ever been exercised before this
note. Nothing in `CHANGELOG.md` recorded a run of it, and the only mention of the RAW
path anywhere in the docs at the time was an aside about a missing TTL cmsg.
Treat it as never-exercised rather than as a regression.

The v6 RAW promiscuity is separately real. A raw ICMPv6 socket receives ICMPv6
traffic the host sees, not merely replies to this probe — neighbour discovery,
MLD, another process's echo replies. yo's only filter is `type == 129`, so any
type-129 frame is accepted and its RTT recorded against yo's own `t0`. In the
loopback capture the raw socket also observed yo's own outbound request
(`type=128`) ahead of the reply; in the lock-step loop that single unexpected
frame consumes the probe's one recv and the real reply is never read.

## How it was fixed

All four remedies landed together in 0.6.0, because items 1 and 4 are only
correct as a pair: stripping the header without looping still loses the probe to
yo's own outbound request, and looping without stripping still never matches.

1. **`_lx_strip_ipv4_header(buf, n, ttl_out)`** (`src/platform_linux.cyr`) —
   removes the IPv4 header in place on the RAW path and returns the new length.
   It reads `ihl` from the low nibble rather than assuming 20, refuses to strip
   anything whose version nibble is not 4 or whose IHL is below the minimum (so a
   mis-detection degrades to the old behaviour instead of corrupting a frame), and
   lifts the real TTL from header offset 8 — but only when the cmsg walk found
   none, so `IP_RECVTTL` always wins. Pure, and unit-tested as
   `raw ipv4 header strip` in `tests/yo.tcyr` (13 assertions, mutation-checked:
   neutering the helper turns 7 of them red).
2. **`ident` matched when the RAW fallback is in play**, gated on the new
   `platform_icmp_raw_mode()` — 1 on the Linux RAW path, 0 on DGRAM and 0 on
   AGNOS. Gating is essential: SOCK_DGRAM replaces ident with the socket-managed
   id, so an unconditional comparison would reject every genuine reply.
3. **`seq` matched unconditionally.** It survives on every path — the kernel
   rewrites ident but never seq, and `_ag_icmp_pong` echoes the stored request.
   Verified after the change on DGRAM v4, DGRAM v6, RAW v4 and AGNOS, all 0% loss.
4. **The recv loops instead of accepting the first frame** (`src/probe.cyr`),
   bounded by a `t0 + timeout_ms * 1000` deadline rather than by one syscall's
   `SO_RCVTIMEO`. On DGRAM the first frame matches and the loop exits immediately,
   so that path is untouched.

Result, same command that reproduced the defect:

```
$ unshare -r -n -- sh -c 'ip link set lo up; ./build/yo -c 3 127.0.0.1'
3 sent · 3 received · 0% loss · min/avg/max = 0.05/0.05/0.07 ms
```

`icmp_verify` stays unused in the probe path even now. On DGRAM and v6 the kernel
has already validated the checksum; on RAW the strip is a prerequisite, and once
the offset is right the check duplicates what `icmp_rcv` did. It remains
test-only by choice, not by oversight.

## `icmp_verify` is test-only

Grep-verified, whole repo, `lib/` excluded:

```
$ grep -rn "icmp_verify" . --exclude-dir=lib --exclude-dir=.git
src/icmp.cyr:70:fn icmp_verify(buf, len): i64 {
CHANGELOG.md:434:- `src/icmp.cyr` — RFC 792 ICMP echo framing + RFC 1071 Internet checksum ...
tests/yo.tcyr:78:    test_group("icmp_verify");
tests/yo.tcyr:80:    assert_eq(icmp_verify(&pkt, 13), 1, "freshly built packet verifies");
tests/yo.tcyr:86:    assert_eq(icmp_verify(&hdronly, 8), 1, "header-only verifies");
tests/yo.tcyr:90:    assert_eq(icmp_verify(&pkt, 13), 0, "tampered packet fails verify");
tests/yo.tcyr:93:    assert_eq(icmp_verify(&pkt, 4), 0, "len<8 rejected");
```

One definition, one changelog mention, four assertions. Zero call sites in
`src/`. Of the other accessors, only `icmp_code` and `icmp_cksum` are still
test-only — `icmp_ident` and `icmp_seq` gained production call sites in 0.6.0
(`probe.cyr:121`, `:126`) when the acceptance check tightened.

This is not dead code to delete. `icmp_verify` documents the RFC 1071 property
that the round-trip depends on (`icmp.cyr:67-69`: a valid message sums to zero
with the checksum field left in place), it is the only test yo has that
`icmp_checksum` is correct in both directions, and it is what `_ag_icmp_pong`'s
synthesised reply is implicitly relying on. Being unreachable from `main`, it
falls in the set `CYRIUS_DCE=1` NOPs (400 functions, 68,740 bytes — which does
not shrink the file; `build/yo` is 152,704 B either way). Keep it; just do not
read its existence as evidence that the probe path checks checksums.

## Reproducing

Needs no root — `unshare -r -n` supplies `CAP_NET_RAW` inside a user+network
namespace, and that namespace's default `ping_group_range` (`65534 65534`) is
what forces yo down the fallback.

```sh
# On a build from before 0.6.0 this shows the defect: 100% loss on the RAW path
# against a host that is answering. On 0.6.0+ both lines report 0% loss.
unshare -r -n -- sh -c 'ip link set lo up; ./build/yo -c 2 --diag 127.0.0.1'   # RAW fallback
./build/yo -c 2 127.0.0.1                                                       # DGRAM

# raw v4 delivers the IP header; byte 0 is 0x45, the ICMP type is at +20
unshare -r -n -- sh -c 'ip link set lo up; python3 -c "
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_RAW,socket.IPPROTO_ICMP)
s.settimeout(3); s.sendto(b\"\x08\x00\xe5\xc4\x12\x34\x00\x07\",(\"127.0.0.1\",0))
for _ in range(2):
    d,_x=s.recvfrom(2048); print(len(d), hex(d[0]), d[20])
"'
# -> 28 0x45 8      <- yo would parse this byte 0 (0x45 = 69) as the ICMP type
# -> 28 0x45 0      <- the actual reply, one frame too late for a lock-step recv
```

The namespace changes which socket flavour opens. It does not change the receive
shape: header inclusion on `AF_INET SOCK_RAW` is `raw(7)` behaviour, not a
namespace artifact.

## See also

- `docs/adr/` — the per-backend sovereignty decision this note sits underneath.
- `docs/development/roadmap.md:176` — where this note is listed.
