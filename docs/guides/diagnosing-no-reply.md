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

The RAW path demultiplexes for itself: it matches the sequence number, the
ident (yo's own on RAW, unlike on `SOCK_DGRAM` where the kernel rewrites it),
and on IPv4 the checksum, and it keeps reading until one matches or `-W`
expires, so yo's own outbound request does not consume the read.
- **On a build older than 0.7.2, two yo processes on RAW crossed replies.** The
  ident was the constant `0x1234` in every yo, and on IPv6 RAW it was not
  compared at all, so a dead host probed while another yo pinged a live one
  could report replies and exit 0. Since 0.7.2 the ident is random per process.

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
differently from the others. `-11` is `EAGAIN`: the reply wait ran out. Since
0.7.2 the probe loop waits in `platform_wait_readable` (a `ppoll` against the
`-W` deadline, which Ctrl-C can also end) and records `-11` when that wait runs
out; before, `SO_RCVTIMEO` on a blocking recv produced the same value. Either
way it means the send succeeded and the timeout elapsed with nothing to read.

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
the cyrius wrappers (`sys_icmp_echo_ex`#100, or `sys_icmp_echo`#55 on an agnos
older than 1.56.48; `sys_udp_bind`/`send`/`recv`/`unbind` #51-54; `sys_net_*`
#61; `sys_sigprocmask`/`sys_signalfd` #17/#18; `sys_uptime_ms`#40,
`sys_sleep_ms`#41).

`--diag` matters more here than on Linux, and that is why the flag exists at all.
On agnos there is no `ip addr`, no `dmesg`, no second terminal. When a probe
returns nothing on iron you have the serial console and whatever the tool prints
— so the tool prints the network state itself.

### Worked example — a real capture

From the QEMU smoke (0.8.0), `yo -c 2 -W 500 -i 0 -n --diag 192.0.2.1`. That is
TEST-NET-1, which nothing answers:

```
yo 192.0.2.1 — 24 bytes
  seq=0  timeout
  seq=1  timeout
2 sent · 0 received · 100% loss
  --- diag: no reply from 192.0.2.1 (IPv4) ---
  backend         : agnos (sovereign syscalls)
  net ip          : 10.0.2.15
  netmask         : 255.255.255.0
  gateway         : 10.0.2.2
  dns server      : 10.0.2.3
  echo timeout ms : 500
  icmp_echo_ex#100: -1 (no reply within the timeout above, or NIC down)
  icmp tx         : 2 this run (4 since boot)
  icmp rx         : 0 this run (2 since boot)
  icmp timeouts   : 2 this run (2 since boot)
  pings answered  : 0 this run (0 since boot)
  verdict         : requests left this host and no reply matched: the path or the target dropped them
```

The lease is healthy, both requests left the host, and nothing came back. The
box's network is fine; nothing at that address answers.

### The first fork is the lease

All four `net_config`#61 address fields are populated by the DHCP ACK (agnos
`net_dhcp.cyr`), so they are read as one answer, not four.

#### `net ip: unset`

```
  net ip          : unset
  diagnosis       : no DHCP lease — the NIC never configured; nothing could have been sent
```

`output_diag_kv_ipv4` renders a zero field as `unset` rather than `0.0.0.0`
precisely because the two are different facts. No lease was ever taken: the NIC
never came up, or the DISCOVER/OFFER never completed.

**Nothing about yo is wrong in this case.** There was no address to send from, so
no packet could have left. Debug the NIC and the DHCP path, not the probe. The
`diagnosis` line is emitted only on this condition.

### The second fork is the counters

With a lease in place, the echo returned `-1`. Per its contract (agnos
`kernel/core/syscall.cyr`, `num == 100`) that is either no reply within the
bound or a NIC that is down, and the syscall does not say which. The ICMP
counters do. They are `net_config`#61 fields 4..7, present since agnos
1.56.48:

| Line | Counts |
|---|---|
| `icmp tx` | echo requests the kernel sent |
| `icmp rx` | echo replies that matched a waiting request (identifier and sequence) |
| `icmp timeouts` | waits that ran out without a match |
| `pings answered` | inbound echo requests this kernel answered: someone pinged *us* |

They are kernel-wide and never reset, so yo samples them when the target begins
and prints how far each moved, `N this run`, beside the total. The `verdict` line
reads the movement:

- **`no echo request left this host`** — tx did not move. It is a local fault: the
  NIC, the route to the next hop, or a failed send. The network was never tried.
- **`requests left this host and no reply matched`** — tx moved and rx did not.
  The fault is the path or the target, not this machine. Probe the gateway next
  (`yo --diag -c 2 <the gateway from the dump>`): a reply there and silence from
  the target puts the fault past your first hop.
- **`the kernel matched replies, none of them yo's`** — rx moved, yet yo got
  nothing. A late reply cannot do this, because the kernel clears the wait at
  the deadline. Another process was pinging during the run, and the counters
  are shared. Run yo again on its own.

A non-zero `pings answered` total is a cheap witness that inbound ICMP and the
reply path work on this box.

On a kernel older than 1.56.48 the counters do not exist; the dump says
`icmp counters: unavailable` and the fork above is the only one there is.

### `-W` on the AGNOS backend

Since 0.8.0, `-W` is the reply bound on AGNOS too. `icmp_echo_ex`#100 is still
**one-shot**: it sends one echo, blocks for the reply, and returns the RTT in
milliseconds (`>= 0`) or `-1`. Its timeout is a parameter, and yo passes `-W`.
The `echo timeout ms` line shows the bound the kernel was given. Two limits
apply:

- **The kernel caps the bound at 60 s.** A larger `-W` waits 60 s, and the line
  says 60000.
- **An agnos older than 1.56.48 has no #100.** yo detects that once per run (the
  counters arrived in the same agnos commit, so field 4 answering -1 is the
  tell) and falls back to `icmp_echo`#55, whose bound is a fixed ~3 s. The dump
  then says `this kernel has no icmp_echo_ex#100 … so -W was not applied`, and
  the echo line reads `icmp_echo #55`. Raising `-W` there is wasted effort.

Two related consequences of the same contract, worth knowing before you read them
as bugs:

- **`rtt=0.00 ms` is normal.** The RTT yo prints is measured host-side with
  `uptime_ms`#40 at 1 ms resolution, so any sub-millisecond reply prints 0.
- **A successful probe is a synthesised reply.** `_ag_icmp_pong` is the model
  bridge: yo's surface is POSIX-shaped (`open` → `send_to` → `recv_ext`) but
  the echo is one-shot. `send_to` stores the request; `recv_ext` calls the echo,
  then hands the stored request back with type flipped 8→0 and the RFC-1071
  checksum recomputed via yo's own `icmp_checksum`. The RTT yo prints is
  measured host-side across `send_to`..`recv_ext`. The wire bytes yo parses on
  agnos are its own — it is validating the bridge, not the reply frame.

### Ctrl-C on the AGNOS backend

**Ctrl-C at the agnos console stops nothing.** No console key raises a signal on
agnos (agnos-userland-abi.md § 4.9), so there is no SIGINT to catch. To stop a
long run from the keyboard, use a bounded `-c`.

yo does handle **SIGINT** there. A parent or supervisor that sends one (`kill`#16:
only yo's parent, yo itself or init may) ends the run with its summary, as
Ctrl-C does on Linux. Two limits come from the kernel, where a signal is a
pending bit that wakes no wait:

- **A reply wait runs to its end.** A SIGINT that lands while the echo is waiting
  is seen when the echo returns: at the reply, or at `-W`.
- **The interval sleep is sliced.** It runs in steps of at most 50 ms, checking
  for the signal before each, so a SIGINT there ends the run within about 50 ms.

### Two more AGNOS readings

**`icmp echo: not called`** — no request ever reached the kernel. Either every
send was refused before it (an `-s` over 2040, say, which the 2048-byte request
buffer refuses with `-90 EMSGSIZE`; the send errors above the summary say so),
or a SIGINT ended the run before the first probe.

**`note: no ICMPv6 syscall on agnos …`** — there is no ICMPv6 primitive in ring 3.
`platform_icmp6_open` returns `-1` unconditionally, so a `-6` probe exits 2
having sent nothing. The v6 path on agnos is *unavailable*, not merely silent;
the note line says so.

---

## Reproducing the AGNOS case locally

`scripts/agnos-qemu-smoke.sh` runs the whole thing end to end: it boots a
production agnos kernel against an ext2 rootfs carrying `/bin/agnsh`, `/bin/yo`
and `/bin/yosmoke` (its helper), types the probes at the shell over QMP
`send-key`, and reads the output back out of the serial log. Among its runs:

- the default target, `10.0.2.2` (the SLIRP gateway), which returns
  `2 sent · 2 received · 0% loss`;
- `yo -c 2 -W 500 -i 0 -n --diag 192.0.2.1`, timed in the guest. It is the
  capture above, and the smoke asserts its counter lines and verdict;
- two SIGINT runs, which `yosmoke` sends as yo's parent.

The empty-address failure case is printed on every run, so there is no need to
point the default target at one. (The `ttl=` an AGNOS run prints is always
`64` — a literal, not a hop count.)

The script SKIPs (exit 0) rather than failing when the sibling checkouts
(`../agnos`, `../gnoboot`, `../agnoshi`) or the QEMU/`parted`/`mtools` toolchain
are missing, so a bare machine will not report a false failure. From a git
worktree the siblings are not at `../`; point the script at them:

```sh
AGNOS_ROOT=~/Repos/agnos GNOBOOT_ROOT=~/Repos/gnoboot AGNOSHI_ROOT=~/Repos/agnoshi scripts/agnos-qemu-smoke.sh
```

One host-side caveat the script warns about in its own header: QEMU user-mode
networking forwards guest ICMP through a *host* ping socket, which needs the
host's `net.ipv4.ping_group_range` to include your gid. If that is `0 0` on your
host, no guest can ever get a reply — the `ping_group_range` fix at the top of
this guide applies to the machine running QEMU, not to the guest.

---

## See also

- [`../adr/0002-focused-kernel-icmp-syscall.md`](../adr/0002-focused-kernel-icmp-syscall.md)
  — why the kernel's echo is a focused one-shot primitive, what that costs, and
  (§ Update) how `icmp_echo_ex`#100 gave `-W` back.
- [`getting-started.md`](getting-started.md) — build and test.
