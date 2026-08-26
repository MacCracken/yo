# Diagnosing a probe that gets nothing back

You ran `yo 1.2.3.4` and got this:

```
yo 1.2.3.4 — 56 bytes
  seq=0  timeout
  seq=1  timeout
2 sent · 0 received · 100% loss
```

`100% loss` is a symptom, not a cause. It covers every failure from "the kernel
refused to give us a socket" to "the host is genuinely down". `--diag`, added in
0.5.11, prints the per-backend state that separates them.

## Start here

Re-run with the flag:

```sh
yo --diag -c 2 1.2.3.4
```

`--diag` is long-only — no short letter (`src/cli.cyr:20`; `-D` is reserved for
the POSIX-ping timestamp option). It is **not** gated on `-q`
(`src/probe.cyr:32-35`), so `yo -q --diag <host>` in a health-check script still
prints the reason when the check fails.

The dump fires on exactly two conditions, both in `src/probe.cyr`:

| When | Where | Exit code |
|---|---|---|
| The ICMP socket never opened | `probe.cyr:44`, before the loop | 2 |
| The target ended at `stats_recv(s) == 0` | `probe.cyr:118-119`, after the summary | 1 |

Nothing else triggers it. A run with even one reply prints no dump.

The block prints **after** the summary, indented two spaces, one flat
`  key: value` line per fact (`src/output.cyr:271-309`). The shape is deliberate:
on the AGNOS backend you are reading a serial console, not a terminal, so it has
to `grep` cleanly out of a log.

**Read the fields top to bottom and stop at the first one that failed.** They are
ordered first-fail on purpose, and the fields below a failure are not evidence —
several of them default to zero and print their happy-path string when the code
that would have set them never ran. The specific traps are called out below.

---

## LINUX branch

The Linux backend (`src/platform_linux.cyr`) opens an unprivileged
`AF_INET` / `SOCK_DGRAM` / `IPPROTO_ICMP` socket and falls back to `SOCK_RAW`
(`platform_icmp_open`, `platform_linux.cyr:86-100`). Everything is raw syscall
numbers — `_LX_SYS_SOCKET=41`, `_LX_SYS_SENDTO=44`, `_LX_SYS_RECVMSG=47`. There is
no libc in the path to blame.

### Worked example — a real capture

`192.0.2.1` is TEST-NET-1: routable off this host, nothing answers.

```
yo 192.0.2.1 — 56 bytes
  seq=0  timeout
  seq=1  timeout
2 sent · 0 received · 100% loss
  --- diag: no reply from 192.0.2.1 (IPv4) ---
  backend         : linux (POSIX socket)
  icmp socket     : SOCK_DGRAM (unprivileged)
  ping_group_range: 0 2147483647
  last sendto     : ok (packets left the host)
  last recv       : -11 EAGAIN (timeout — sent, nothing came back within -W)
```

Every local stage is clean. The packets left the host and nothing came back. This
is a network answer, not a yo answer.

### The four questions, in order

`platform_diag_dump` (`platform_linux.cyr:534-596`) answers them in this sequence:

| Line | Rules out | Rules in |
|---|---|---|
| `icmp socket` | — | permission to open an ICMP socket at all |
| `ping_group_range` | gid outside the range | the kernel policy that gates the unprivileged path |
| `last sendto` | local send failure (routing, policy) | the packets reaching the wire |
| `last recv` | local recv failure | a genuine timeout — sent, nothing answered |

---

### `icmp socket: never opened`

Both `socket()` attempts failed. Nothing was sent; the run exited 2 and printed to
stderr first:

```
yo: cannot open ICMP socket — try adjusting /proc/sys/net/ipv4/ping_group_range or run with CAP_NET_RAW
```

Two routes out.

**Widen `ping_group_range`.** The sysctl is a `<lo> <hi>` gid pair; a caller whose
gid falls outside `[lo, hi]` cannot open `SOCK_DGRAM`+`IPPROTO_ICMP` at all. Stock
Debian and Ubuntu ship `0 0` — an *empty* range in practice, because it permits
gid 0 only and gid 0 does not need the unprivileged path. That is the single most
common reason yo works under `sudo` and not otherwise.

```sh
cat /proc/sys/net/ipv4/ping_group_range          # what you have now
sudo sysctl -w net.ipv4.ping_group_range="0 2147483647"   # allow every gid
```

That is not persistent. To keep it, drop a line in `/etc/sysctl.d/`:

```sh
echo 'net.ipv4.ping_group_range = 0 2147483647' | sudo tee /etc/sysctl.d/99-ping-group-range.conf
```

Narrow it to one group instead of `0 2147483647` if you would rather not open it
to everyone — the range is gids, so `1000 1000` permits exactly that group.

**Or grant `CAP_NET_RAW`**, which lets the `SOCK_RAW` fallback succeed regardless
of the sysctl:

```sh
sudo setcap cap_net_raw+ep ./build/yo
```

That is how distro `ping` ships. It also survives the sysctl being `0 0`.

> **Trap — this line lies on the IPv6 path.** `_lx_icmp_mode` is set only by
> `platform_icmp_open` (`platform_linux.cyr:90`, `:96`).
> `platform_icmp6_open` (`:278`) never touches it, so it stays at
> `_LX_ICMP_MODE_NONE` and a `-6` probe reports `never opened` even when the v6
> socket opened fine. A real capture from this host:
>
> ```
>   --- diag: no reply from 2001:db8::1 (IPv6) ---
>   backend         : linux (POSIX socket)
>   icmp socket     : never opened
>   ping_group_range: 0 2147483647
>   last sendto     : -101
>   last recv       : no error recorded
> ```
>
> The socket opened — exit was 1, not 2, and the probe reached `sendto`, which
> returned `-101 ENETUNREACH` because this host has no route to `2001:db8::1`.
> On a `-6` run, ignore the `icmp socket` line and read `last sendto`.

---

### `icmp socket: SOCK_RAW (privileged fallback)`

The unprivileged `SOCK_DGRAM` open was refused and the `SOCK_RAW` retry succeeded
— so you are running as root, or the binary carries `CAP_NET_RAW`. This is not
itself the cause of a silent probe; keep reading down the block. But two things
are worth knowing:

- Your `ping_group_range` is almost certainly too narrow for your gid. The same
  probe run by an unprivileged user on this box will fail outright. A container
  or a fresh network namespace defaults to `65534 65534`, which excludes
  essentially everyone — that is the usual way to end up here without meaning to.
- **On a build older than 0.6.0, this line WAS the cause.** The RAW path did not
  strip the IPv4 header that `raw(7)` prepends to every received packet, so yo
  read `0x45` where the ICMP type should be and scored every genuine reply as a
  timeout — 100% loss against a host that was answering, with a `--diag` block
  that looked exactly like a network problem. If you are on 0.5.x and see
  `SOCK_RAW` here, **that is your bug**; upgrade. Details in
  [architecture note 001](../architecture/001-reply-acceptance-invariants.md).

Since 0.6.0 the RAW path demultiplexes for itself — it matches the sequence
number, and the ident too (which is yo's own `0x1234` on RAW, unlike on
`SOCK_DGRAM` where the kernel rewrites it), and it keeps reading until one
matches or `-W` expires. So a second `yo` racing on the same box no longer
crosses replies, and yo's own outbound request no longer consumes the read.

---

### `last sendto: <negative>`

A negative value here is conclusive: the packets never left. The number is the
kernel's negated errno, printed raw (`output_diag_kv_int`) because decoding a
table of them into strings is not worth the bytes on a path that only runs when
something is already wrong.

| Value | errno | Usual meaning |
|---|---|---|
| `-1` | `EPERM` | a firewall or LSM rejected the send — commonly an `iptables`/`nftables` OUTPUT rule, or a sandbox policy |
| `-13` | `EACCES` | permission denied on the send itself; on `SOCK_DGRAM` typically a broadcast/multicast destination without the matching socket option |
| `-101` | `ENETUNREACH` | no route to the destination — the address family is unrouted here (see the IPv6 capture above), or the interface is down |

For anything else, `errno 101` etc. against `/usr/include/asm-generic/errno-base.h`
and `errno.h`; the sign is yo's, the magnitude is the kernel's.

`ENETUNREACH` on a v6 target usually means the host has no IPv6 route at all —
check `ip -6 route` before suspecting yo.

> **Trap — `ok (packets left the host)` is a default, not a measurement.**
> `_lx_last_send_err` starts at 0 and is only ever assigned on a *failed* send
> (`platform_linux.cyr:150`, `:300`). The dump prints the `ok` string whenever it
> is 0 (`:517-519`), including when the socket never opened and `sendto` was never
> called. If the line above says `never opened`, the `last sendto` and `last recv`
> lines below it carry no information. Same for `last recv: no error recorded`.

---

### `last recv: -11 EAGAIN (timeout — sent, nothing came back within -W)`

This is the one case that gets words instead of a number, because it reads so
differently from the others. `-11` is `EAGAIN`: `SO_RCVTIMEO` fired.
`platform_set_recv_timeout_ms` (`platform_linux.cyr:118`) applies `-W` to the socket
before the loop, so this means the send succeeded and the timeout elapsed with
nothing to read.

That is a genuine network timeout. The host is down, the reply is filtered, or
`-W` is too short. In order:

1. **Raise `-W`.** The default is 1000 ms (`YO_DEFAULT_TIMEOUT_MS`,
   `src/cli.cyr:27`). Satellite links, congested WAN paths, and a first packet
   that has to wait on ARP/ND all beat that.

   ```sh
   yo --diag -c 4 -W 5000 1.2.3.4
   ```

2. **Compare against system `ping`.** If `ping` also gets nothing, the fault is
   not in yo:

   ```sh
   ping -c 4 -W 5 1.2.3.4
   ```

   If `ping` gets replies and yo does not, that is a yo bug — the `--diag` block
   plus both outputs is the bug report.

3. **Check whether the target filters ICMP echo.** Plenty of hosts drop echo
   requests silently by policy. There is no way to tell that apart from "down"
   from the probe side; that is ICMP, not a gap in yo.

---

## AGNOS branch

The AGNOS backend (`src/platform_agnos.cyr`) shares no code with the Linux one —
per-backend sovereignty. No POSIX, no sockets: sovereign ring-3 syscalls through
the cyrius wrappers (`sys_icmp_echo`#55, `sys_udp_bind`/`send`/`recv`/`unbind`
#51-54, `sys_net_dns_server`#61 field 3, `sys_uptime_ms`#40, `sys_sleep_ms`#41).

`--diag` matters more here than on Linux, and that is why the flag exists at all
(`platform_agnos.cyr:170-189`). On agnos there is no `ip addr`, no `dmesg`, no
second terminal. When a probe returns nothing on iron you have the serial console
and whatever the tool prints — so the tool prints the network state itself.

### Worked example — a real capture

From the QEMU smoke against `10.0.2.99`, an address with nothing behind it:

```
  --- diag: no reply from 10.0.2.99 (IPv4) ---
  backend         : agnos (sovereign syscalls)
  net ip          : 10.0.2.15
  netmask         : 255.255.255.0
  gateway         : 10.0.2.2
  dns server      : 10.0.2.3
  icmp_echo #55   : -1 (timed out at the kernel's fixed ~3 s bound, or NIC down)
```

Healthy lease, echo timed out. The box's network is fine; that address is empty.

### The first fork is the lease

All four `net_config`#61 fields are populated by the DHCP ACK (agnos
`net_dhcp.cyr`), so they are read as one answer, not four.

#### `net ip: unset`

```
  net ip          : unset
  diagnosis       : no DHCP lease — the NIC never configured; nothing could have been sent
```

`output_diag_kv_ipv4` renders a zero field as `unset` rather than `0.0.0.0`
(`src/output.cyr:304-309`) precisely because the two are different facts. No lease
was ever taken: the NIC never came up, or the DISCOVER/OFFER never completed.

**Nothing about yo is wrong in this case.** There was no address to send from, so
no packet could have left. Debug the NIC and the DHCP path, not the probe. The
`diagnosis` line is emitted only on this condition (`platform_agnos.cyr:204`).

#### Lease present but `icmp_echo #55: -1`

The lease is good and the kernel's one-shot echo returned `-1`. Per the
`icmp_echo`#55 contract (agnos `kernel/core/syscall.cyr`, `num == 55`) that is
either:

- the reply did not arrive inside the kernel's **fixed ~3 s bound**, or
- the NIC is down.

The syscall does not distinguish them, so neither does yo. From here: probe the
gateway first (`yo --diag -c 2 <the gateway from the dump>`). A reply from the
gateway and silence from the target puts the fault past your first hop; silence
from both puts it at the NIC or the link.

### `-W` does not apply on the AGNOS backend

This is the most common surprise. `icmp_echo`#55 is **one-shot**: it sends one
echo, blocks for the reply, and returns the RTT in milliseconds (`>= 0`) or `-1`.
The timeout is a fixed bound inside the kernel's `icmp_ping` and is not a
parameter, so there is nothing for yo to pass.

Mechanically: `-W` reaches `platform_set_recv_timeout_ms`, which stores it in
`_ag_timeout_ms` (`platform_agnos.cyr:114-117`) — and the only reader of that
variable is `platform_udp_recv`'s deadline, the DNS path (`:97`). The ICMP path
(`_ag_icmp_pong`, `:59-74`) never consults it. So `-W` still shapes hostname
*resolution* on agnos; it has no effect whatsoever on the echo. Raising it to
work around a `-1` is wasted effort. See the ADR linked below for why the syscall
is shaped that way.

Two related consequences of the same contract, worth knowing before you read them
as bugs:

- **`rtt=0.00 ms` is normal.** The kernel's RTT resolution is the 100 Hz tick
  (10 ms), so any sub-10 ms reply comes back as 0.
- **A successful probe is a synthesised reply.** `_ag_icmp_pong` is the model
  bridge: yo's surface is POSIX-shaped (`open` → `send_to` → `recv_ext`) but
  `icmp_echo` is one-shot. `send_to` stores the request; `recv_ext` calls
  `icmp_echo`, then hands the stored request back with type flipped 8→0 and the
  RFC-1071 checksum recomputed via yo's own `icmp_checksum`. The RTT yo prints is
  measured host-side across `send_to`..`recv_ext`. The wire bytes yo parses on
  agnos are its own — it is validating the bridge, not the reply frame.

### Two more AGNOS readings

**`icmp_echo #55: 0`** — a non-negative value prints as a bare integer
(`platform_agnos.cyr:212`). Since any `rtt >= 0` makes `_ag_icmp_pong`
synthesise a reply, which makes `stats_recv(s) > 0`, which suppresses the dump, a
`0` here means the syscall was **never called** — not that the RTT was zero. In
practice that is the `-6` case below.

**`note: no ICMPv6 syscall on agnos …`** — there is no ICMPv6 primitive in ring 3.
`platform_icmp6_open` returns `-1` unconditionally (`platform_agnos.cyr:153`), so
a `-6` probe exits 2 at `probe.cyr:44` having sent nothing. The v6 path on agnos
is *unavailable*, not merely silent; the note line says so
(`platform_agnos.cyr:195`).

---

## Reproducing the AGNOS case locally

`scripts/agnos-qemu-smoke.sh` runs the whole thing end to end: it boots a
production agnos kernel against an ext2 rootfs carrying `/bin/agnsh` and
`/bin/yo`, types the probe at the shell over QMP `send-key`, and echoes the
`--diag` block out of the serial log. Point it at an empty address to get the
failure case:

```sh
YO_SMOKE_TARGET=10.0.2.99 scripts/agnos-qemu-smoke.sh
```

That is the run the `10.0.2.99` capture above came from — it reports `100% loss`
and exits non-zero, on purpose. The default target is `10.0.2.2`, the SLIRP
gateway, which returns `2 sent · 2 received · 0% loss`. (The `ttl=` an AGNOS run
prints is always `64` — a literal, not a hop count.)

The script SKIPs (exit 0) rather than failing when the sibling checkouts
(`../agnos`, `../gnoboot`, `../agnoshi`) or the QEMU/`parted`/`mtools` toolchain
are missing, so a bare machine will not report a false failure.

One host-side caveat the script warns about in its own header: QEMU user-mode
networking forwards guest ICMP through a *host* ping socket, which needs the
host's `net.ipv4.ping_group_range` to include your gid. If that is `0 0` on your
host, no guest can ever get a reply — the `ping_group_range` fix at the top of
this guide applies to the machine running QEMU, not to the guest.

---

## See also

- [`../adr/0002-focused-kernel-icmp-syscall.md`](../adr/0002-focused-kernel-icmp-syscall.md)
  — why `icmp_echo`#55 is a focused one-shot primitive, and therefore why `-W`
  cannot be honoured on the AGNOS backend.
- [`getting-started.md`](getting-started.md) — build and test.
