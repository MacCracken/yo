#!/bin/bash
# agnos-qemu-smoke — does `yo` actually RUN on AGNOS, and does a probe come back?
#
# WHY THIS EXISTS. yo's AGNOS backend (src/platform_agnos.cyr) has been
# compile-gated only. `cyrius build --agnos` proves it assembles; it does not
# prove `icmp_echo`#55 is reached, that the one-shot bridge in `_ag_icmp_pong`
# synthesises a reply yo's own parser accepts, or that the RTT is sane. The only
# evidence it ever worked is two manual iron burns in agnos's CHANGELOG (1.45.16:
# `yo google.com` 2/4 = 50% loss, RX-ring overflow; 1.51.7 on 2026-07-02: 4/4 at
# 0% loss). Manual burns are not a regression gate — nothing catches a break
# between them. This is that gate. It is manual (roadmap.md § 0.8.x weighs running
# it in CI).
#
# HOW IT DRIVES THE SHELL. agnos has NO serial RX path — console input comes from
# `kbd_read_blocking` (kernel/core/syscall.cyr), a USB-keyboard read. So
# `-serial stdio` is output-only and piping to QEMU's stdin reaches nothing. The
# working shape is the one agnosticos/scripts/qemu-fb-smoke.sh established:
# give the guest `-device qemu-xhci` + `-device usb-kbd,bus=xhci.0`, attach a QMP
# socket, and type with QMP `send-key`. Serial goes to a file and is polled for
# markers. That is what this does.
#
# GATES
#   load-bearing : /bin/yo loads and runs in ring 3 (its banner reaches serial)
#   load-bearing : it prints a summary line, no #PF / PANIC
#   load-bearing : replies received, 0% loss   [see SLIRP note]
#   load-bearing : -s 3000 is refused with EMSGSIZE (audit D)
#   load-bearing : -W is the reply bound (icmp_echo_ex#100): two probes at -W 500
#                  against an unreachable address take ~1 s, not #55's ~6 s
#   load-bearing : --diag prints the ICMP counters for this run (tx moved by 2,
#                  rx did not) and says the requests left the host
#   load-bearing : SIGINT ends a run: in the interval sleep within ~one slice,
#                  with a summary; during the last probe's reply wait, without
#                  starting the next target
#
# THE SIGINT HELPER. agnos lets only a process's parent, the process itself or
# init signal it, no console key raises SIGINT, and agnsh has no kill builtin.
# tests/agnos/yosmoke.cyr is a small parent that spawns yo, signals it and
# times it; it goes on the image as /bin/yosmoke. It times the -W run too, so
# the measurement stays inside the guest, away from QMP typing and serial polling.
#
# SLIRP NOTE. QEMU user-mode networking forwards guest ICMP through a host ping
# socket, which needs the host's net.ipv4.ping_group_range to include the calling
# gid. Where it does not, no guest can ever get a reply and the reply gate would
# assert a property of the HOST, not of yo — so that case is probed up front and
# downgraded to INFO. `yo --diag` output is echoed either way, precisely so the
# two causes are distinguishable in the log.
#
# Missing prerequisites => SKIP (exit 0), never FAIL: this cannot be a required
# gate on a machine without the sibling checkouts.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGNOS_ROOT="${AGNOS_ROOT:-$ROOT/../agnos}"
GNOBOOT_ROOT="${GNOBOOT_ROOT:-$ROOT/../gnoboot}"
AGNOSHI_ROOT="${AGNOSHI_ROOT:-$ROOT/../agnoshi}"

# 10.0.2.2 is the SLIRP gateway — the only host reliably reachable from a
# user-mode-networked guest with no outbound assumptions.
TARGET="${YO_SMOKE_TARGET:-10.0.2.2}"
# An address nothing answers: TEST-NET-1 (RFC 5737) is never routed. SLIRP hands
# the echo to a host ping socket, and it dies there or upstream.
UNREACH="${YO_SMOKE_UNREACH:-192.0.2.1}"
COUNT="${YO_SMOKE_COUNT:-2}"
PROMPT="${YO_SMOKE_PROMPT:-\[ASSIST\] >}"
BOOT_TIMEOUT="${YO_SMOKE_BOOT_TIMEOUT:-120}"
RUN_TIMEOUT="${YO_SMOKE_RUN_TIMEOUT:-90}"

rc=0
skip() { echo "SKIP: $*"; exit 0; }
fail() { echo "  FAIL: $*"; rc=1; }
pass() { echo "  PASS: $*"; }

for tool in qemu-system-x86_64 parted mformat mmd mcopy sgdisk mkfs.ext2 dd tr python3 flock mktemp; do
    command -v "$tool" >/dev/null 2>&1 || skip "required tool '$tool' not on PATH"
done

OVMF_CODE=""
for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd; do
    [ -f "$c" ] && { OVMF_CODE="$c"; break; }
done
OVMF_VARS_SRC=""
for c in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.fd \
         /usr/share/OVMF/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS_4M.fd; do
    [ -f "$c" ] && { OVMF_VARS_SRC="$c"; break; }
done
[ -n "$OVMF_CODE" ]     || skip "OVMF firmware not found (install edk2-ovmf / ovmf)"
[ -n "$OVMF_VARS_SRC" ] || skip "OVMF vars template not found"

GNOBOOT="$GNOBOOT_ROOT/build/BOOTX64.EFI"
AGNOS_KERNEL="${AGNOS_KERNEL:-$AGNOS_ROOT/build/agnos}"
AGNSH="${AGNSH_BIN:-$AGNOSHI_ROOT/build/agnsh_agnos}"
[ -f "$GNOBOOT" ]      || skip "gnoboot not built at $GNOBOOT"
[ -f "$AGNOS_KERNEL" ] || skip "agnos kernel not built at $AGNOS_KERNEL (sh scripts/build.sh in agnos)"
[ -f "$AGNSH" ]        || skip "agnsh not built at $AGNSH (cyrius build --agnos src/agnsh.cyr build/agnsh_agnos in agnoshi)"

echo "=== yo on AGNOS — QEMU smoke ==="
echo "  building yo for the agnos target..."
( cd "$ROOT" && cyrius build --agnos src/main.cyr build/yo-agnos ) >/dev/null 2>&1 \
    || { echo "  FAIL: cyrius build --agnos failed"; exit 1; }
YO_BIN="$ROOT/build/yo-agnos"
[ -f "$YO_BIN" ] || { echo "  FAIL: $YO_BIN missing after build"; exit 1; }
( cd "$ROOT" && cyrius build --agnos tests/agnos/yosmoke.cyr build/yosmoke-agnos ) >/dev/null 2>&1 \
    || { echo "  FAIL: cyrius build --agnos of tests/agnos/yosmoke.cyr failed"; exit 1; }
YOSMOKE_BIN="$ROOT/build/yosmoke-agnos"

# Can the host forward guest ICMP at all? See SLIRP NOTE.
PGR="$(cat /proc/sys/net/ipv4/ping_group_range 2>/dev/null || echo '1 0')"
PGR_LO="$(echo "$PGR" | awk '{print $1}')"
PGR_HI="$(echo "$PGR" | awk '{print $2}')"
MYGID="$(id -g)"
SLIRP_ICMP=1
if [ "$MYGID" -lt "$PGR_LO" ] || [ "$MYGID" -gt "$PGR_HI" ]; then SLIRP_ICMP=0; fi

echo "  agnos kernel : $AGNOS_KERNEL ($(stat -c%s "$AGNOS_KERNEL") B)"
echo "  yo (agnos)   : $YO_BIN ($(stat -c%s "$YO_BIN") B)"
echo "  target       : $TARGET (count=$COUNT) · unreachable: $UNREACH"
echo "  host ICMP    : gid=$MYGID vs ping_group_range='$PGR' -> slirp_icmp=$SLIRP_ICMP"
echo ""

WORK="$ROOT/build/agnos-smoke"
mkdir -p "$ROOT/build"
# One run at a time: the work directory is fixed and wiped below, so a second
# concurrent run would delete the first one's image under its QEMU.
exec 9>"$ROOT/build/agnos-smoke.lock"
flock -n 9 || skip "another agnos-qemu-smoke run holds $ROOT/build/agnos-smoke.lock"
rm -rf "$WORK"; mkdir -p "$WORK"
IMG="$WORK/agnos-yo.img"
SEED="$WORK/seed"; mkdir -p "$SEED/bin"
cp "$AGNSH"  "$SEED/bin/agnsh"
cp "$YO_BIN" "$SEED/bin/yo"
cp "$YOSMOKE_BIN" "$SEED/bin/yosmoke"
chmod +x "$SEED/bin/agnsh" "$SEED/bin/yo" "$SEED/bin/yosmoke"

PART_OFFSET=$(( 33 * 1048576 ))
PART_BYTES=$(( 67 * 1048576 ))
PART_BLOCKS=$(( PART_BYTES / 4096 ))
# Conservative feature set — agnos's ext2 driver implements none of
# metadata_csum / 64bit / dir_index. Same list its own smokes use.
EXT2_FEATURES="${EXT2_SMOKE_FEATURES:-^resize_inode,^dir_index,^metadata_csum,^64bit,^uninit_bg}"

# Each image step is checked: one that failed used to go unnoticed until the
# boot, where it surfaced as "never reached the agnsh prompt".
img_step() { "$@" || { echo "  FAIL: image build step failed: $*"; exit 1; }; }
img_step dd if=/dev/zero of="$IMG" bs=1M count=128 status=none
img_step parted -s "$IMG" mklabel gpt \
    mkpart ESP fat32 1MiB 33MiB set 1 esp on \
    mkpart agnos-fs ext2 33MiB 100MiB
img_step sgdisk -t 2:8300 "$IMG" >/dev/null
img_step mformat -i "$IMG"@@1048576 -F
img_step mmd -i "$IMG"@@1048576 ::EFI ::EFI/BOOT ::boot
img_step mcopy -i "$IMG"@@1048576 "$GNOBOOT" ::EFI/BOOT/BOOTX64.EFI
img_step mcopy -i "$IMG"@@1048576 "$AGNOS_KERNEL" ::boot/agnos
img_step mkfs.ext2 -F -q -L AGNOS-YO -b 4096 -m 0 -O "$EXT2_FEATURES" \
    -d "$SEED" -E offset=$PART_OFFSET "$IMG" $PART_BLOCKS

cp "$OVMF_VARS_SRC" "$WORK/vars.fd"; chmod +w "$WORK/vars.fd"

LOG="$WORK/serial.log"
QLOG="$WORK/qemu.log"
# The QMP socket goes in a short temporary directory: a Unix socket path is
# limited to 108 bytes, and $WORK under a deep checkout can exceed it.
QMP_DIR="$(mktemp -d /tmp/yo-qmp.XXXXXX)"
QMP="$QMP_DIR/qmp.sock"
: > "$LOG"

KVM_ARGS="-cpu max"
[ -r /dev/kvm ] && KVM_ARGS="-enable-kvm -cpu host"

echo "  booting (xhci + usb-kbd, QMP on $QMP)..."
# shellcheck disable=SC2086
qemu-system-x86_64 \
    -machine q35 -m 512M $KVM_ARGS \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$WORK/vars.fd" \
    -drive "file=$IMG,format=raw,if=none,id=disk0" \
    -device "nvme,drive=disk0,serial=AGNOS-YO" \
    -netdev "user,id=u1" \
    -device "virtio-net-pci,netdev=u1" \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 \
    -serial file:"$LOG" \
    -display none \
    -qmp "unix:$QMP,server,nowait" \
    -no-reboot \
    >"$QLOG" 2>&1 &
QPID=$!

cleanup() {
    if kill -0 "$QPID" 2>/dev/null; then
        kill -TERM "$QPID" 2>/dev/null || true
        _g=0
        while [ "$_g" -lt 20 ]; do
            kill -0 "$QPID" 2>/dev/null || break
            sleep 0.1; _g=$(( _g + 1 ))
        done
        kill -0 "$QPID" 2>/dev/null && kill -KILL "$QPID" 2>/dev/null || true
    fi
    wait "$QPID" 2>/dev/null || true
    rm -rf "$QMP_DIR"
    sync
}
trap cleanup EXIT

# Read the serial log as text. `strings` is 7-bit and would BREAK LINES on yo's
# UTF-8 separators (— and ·), mangling both the rendered output and any
# line-anchored match; stripping NULs keeps the multi-byte characters intact.
logtext() { tr -d '\000' < "$LOG"; }

# Wait for a marker in the serial log. -a: the log carries NUL bytes, and grep
# would otherwise call it binary and stay silent.
wait_for() {
    _m="$1"; _max="$2"; _i=0; _ticks=$(( _max * 4 ))
    while [ "$_i" -lt "$_ticks" ]; do
        grep -qa -- "$_m" "$LOG" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.25
        _i=$(( _i + 1 ))
    done
    return 1
}

# Type a line on the guest's USB keyboard via QMP `send-key`, then Enter.
# Paced deliberately: agnos's own notes record sendkey DROPPING characters when
# the guest is busy, so each key gets its own send-key round-trip plus a small
# hold — a dropped character here would look like a yo failure.
type_line() {
    python3 -I - "$QMP" "$1" <<'PY'
import json, socket, sys, time

sock_path, line = sys.argv[1], sys.argv[2]

QCODE = {
    ' ': 'spc', '-': 'minus', '.': 'dot', '/': 'slash', ',': 'comma',
    '=': 'equal', ':': 'shift+semicolon', '_': 'shift+minus',
}
for c in 'abcdefghijklmnopqrstuvwxyz0123456789':
    QCODE[c] = c
for c in 'abcdefghijklmnopqrstuvwxyz':
    QCODE[c.upper()] = 'shift+' + c            # -W

s = socket.socket(socket.AF_UNIX)
s.connect(sock_path)
f = s.makefile('rwb', buffering=0)
json.loads(f.readline())                       # greeting
f.write(b'{"execute":"qmp_capabilities"}\n')
json.loads(f.readline())                       # ack

def send(keys):
    payload = {"execute": "send-key", "arguments": {
        "keys": [{"type": "qcode", "data": k} for k in keys],
        "hold-time": 50,
    }}
    f.write(json.dumps(payload).encode() + b'\n')
    while True:
        line = f.readline()
        if not line:
            return
        msg = json.loads(line)
        if 'return' in msg or 'error' in msg:
            if 'error' in msg:
                print("QMP error:", msg['error'], file=sys.stderr)
            return

for ch in line:
    q = QCODE.get(ch)
    if q is None:
        print("unmappable char %r — extend QCODE" % ch, file=sys.stderr)
        sys.exit(2)
    send(q.split('+'))
    time.sleep(0.06)

send(['ret'])
s.close()
PY
}

# Count prompt occurrences (not lines: the prompt has no trailing newline, so it
# shares a line with whatever is typed next).
prompt_count() { logtext | grep -oa -- "$PROMPT" 2>/dev/null | wc -l; }

# Wait until a NEW prompt appears beyond the baseline count.
wait_for_prompt_return() {
    _base="$1"; _max="$2"; _i=0; _ticks=$(( _max * 4 ))
    while [ "$_i" -lt "$_ticks" ]; do
        [ "$(prompt_count)" -gt "$_base" ] && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.25
        _i=$(( _i + 1 ))
    done
    return 1
}

if wait_for "$PROMPT" "$BOOT_TIMEOUT"; then
    pass "reached the agnsh prompt"
else
    fail "never reached the agnsh prompt within ${BOOT_TIMEOUT}s"
    echo ""; echo "  --- serial tail ---"; logtext | tail -25 | sed 's/^/  /'
    echo ""; echo "  --- qemu output ---"; tail -10 "$QLOG" | sed 's/^/  /'
    cleanup; trap - EXIT
    echo ""; echo "agnos-qemu-smoke: FAIL"; exit 1
fi

# Let the DHCP lease settle — the prompt can appear before the ACK lands.
sleep 3

# Bareword launch: agnsh resolves `yo` to /bin/yo. Using the bareword rather
# than `run /bin/yo` deliberately — it is what a user types, so the launcher
# path gets exercised too. --diag makes a zero-reply run self-explaining.
PROMPTS_BEFORE="$(prompt_count)"
CMD="yo -c $COUNT --diag $TARGET"
echo "  typing: $CMD"
if ! type_line "$CMD"; then
    fail "QMP send-key failed"
    cleanup; trap - EXIT
    echo ""; echo "agnos-qemu-smoke: FAIL"; exit 1
fi

if wait_for "% loss" "$RUN_TIMEOUT"; then
    pass "/bin/yo ran in ring 3 and printed a summary"
else
    fail "no yo summary line within ${RUN_TIMEOUT}s (did /bin/yo load?)"
fi

# ⛔ DO NOT STOP AT "% loss". On a failed probe the --diag block prints AFTER the
# summary, so killing QEMU on the summary truncates exactly the output --diag
# exists to produce. agnos's own scripts/smoke/lib/qemu-dwell.sh warns about this
# shape in its header. The command is finished when the PROMPT COMES BACK, so
# wait for one more prompt than we counted before typing.
if wait_for_prompt_return "$PROMPTS_BEFORE" 20; then
    pass "agnsh returned to its prompt (command completed, output flushed)"
else
    echo "  INFO: prompt did not return within 20s — output may be truncated"
fi

# A second command, for audit finding D: on AGNOS the request is copied into a
# 2048-byte global, and `-s 3000` used to overrun it into the globals after it.
# It must now refuse the send with EMSGSIZE and still print a summary.
PROMPTS_BEFORE="$(prompt_count)"
CMD2="yo -c 1 -n -s 3000 $TARGET"
echo "  typing: $CMD2"
if type_line "$CMD2"; then
    wait_for_prompt_return "$PROMPTS_BEFORE" 30 || echo "  INFO: prompt did not return after the -s 3000 run"
else
    fail "QMP send-key failed (second command)"
fi

# Type a command and wait for the prompt to come back. A run that does not
# return in time is reported by its own assertions below (its yosmoke line is
# missing); the INFO says why the later output may be mangled.
run_cmd() {
    _before="$(prompt_count)"
    echo "  typing: $1"
    if type_line "$1"; then
        wait_for_prompt_return "$_before" "$2" || echo "  INFO: prompt did not return within ${2}s after: $1"
    else
        fail "QMP send-key failed: $1"
    fi
}

# -W through icmp_echo_ex#100, timed in the guest, with the --diag counters. Two
# probes, -W 500, no interval: ~1 s. On #55 each would wait its fixed ~3 s.
CMD3="yosmoke time /bin/yo -c 2 -W 500 -i 0 -n -s 24 --diag $UNREACH"
run_cmd "$CMD3" 30

# SIGINT in the interval sleep. -i 2000 puts 3200 ms mid-sleep whether or not
# replies come back (probes at 0/2000 with replies, 0/2500 without), so a
# sliced sleep sees it within ~one 50 ms slice and a whole 2 s sleep would not.
CMD4="yosmoke sigint 3200 /bin/yo -c 30 -W 500 -i 2000 -n -s 40 $TARGET"
run_cmd "$CMD4" 30

# SIGINT during the last probe's reply wait, with a second target queued. The
# wait cannot be interrupted on agnos, so yo sees the signal when it ends; the
# second target must not start (probe_run's post-loop check).
CMD5="yosmoke sigint 700 /bin/yo -c 1 -W 2000 -n -s 41 $UNREACH $TARGET"
run_cmd "$CMD5" 30

cleanup; trap - EXIT

# The serial lines a typed command printed: everything after the line that
# echoes it, up to the next prompt. ENVIRON, not -v: awk would read the
# backslashes in $PROMPT as escapes.
segment() { logtext | C="$1" P="$PROMPT" awk 'f && $0 ~ ENVIRON["P"] { exit } f { print } index($0, ENVIRON["C"]) { f = 1 }'; }

# A field of a run's `yosmoke: <mode> exit=E ms=M kill=K done` line, or empty.
ys_field() { segment "$1" | sed -n "s/.*yosmoke: [a-z]* .*$2=\(-\{0,1\}[0-9]*\).* done.*/\1/p" | head -1; }

echo ""
echo "  --- yo output ---"
for _c in "$CMD" "$CMD2" "$CMD3" "$CMD4" "$CMD5"; do
    echo "  > $_c"
    segment "$_c" | sed 's/^/    /'
done
echo ""

# --- assertions -------------------------------------------------------
if logtext | grep -qa "kybernet: exec /bin/agnsh"; then
    pass "kybernet exec'd /bin/agnsh"
else
    fail "kybernet never exec'd /bin/agnsh"
fi

if logtext | grep -qa "^yo $TARGET"; then
    pass "yo banner reached serial — the agnos binary executed in ring 3"
else
    fail "no yo banner — /bin/yo did not run"
fi

if logtext | grep -qaE "PANIC|#PF|page fault|GPF|^fault:"; then
    fail "kernel fault during the run"
    logtext | grep -aE "PANIC|#PF|page fault|GPF|^fault:" | head -5 | sed 's/^/    /'
else
    pass "no kernel fault"
fi

if logtext | grep -qa 'send failed: -90 EMSGSIZE'; then
    pass "-s 3000 refused with EMSGSIZE — the 2048-byte request buffer holds (audit D)"
else
    fail "-s 3000 did not report EMSGSIZE (audit D)"
    logtext | grep -a -A 3 -- "^yo $TARGET — 3000 bytes" | sed 's/^/    /'
fi

LOSS_LINE="$(logtext | grep -a '% loss' | head -1)"
# ⛔ ANCHOR THIS. `grep '0% loss'` also matches "10*0% loss*" — an unanchored
# match reported PASS on a 100%-loss run, which is the one result this gate
# exists to catch. Require a non-digit (or start of line) before the 0.
if echo "$LOSS_LINE" | grep -qaE '(^|[^0-9])0% loss'; then
    pass "0% loss — the kernel echo round-tripped: $LOSS_LINE"
else
    if [ "$SLIRP_ICMP" -eq 1 ]; then
        fail "replies expected (this host CAN forward guest ICMP) but got: ${LOSS_LINE:-<none>}"
    else
        echo "  INFO: no replies, and this host cannot forward guest ICMP"
        echo "        (gid $MYGID outside ping_group_range '$PGR') — reply gate not asserted."
        echo "        Widen with: sysctl -w net.ipv4.ping_group_range='0 2147483647'"
    fi
fi

# --- 0.8.0: -W, the --diag counters, SIGINT --------------------------------

# -W: two 500 ms waits, so >= 1000 ms (the kernel bound is never early) and well
# under 2000 ms, which is what -W's 1000 ms default would take. #55 takes ~6 s.
W_MS="$(ys_field "$CMD3" ms)"
if [ -z "$W_MS" ]; then
    fail "-W run: no yosmoke line (did /bin/yosmoke run?)"
elif [ "$W_MS" -ge 950 ] && [ "$W_MS" -lt 1700 ]; then
    pass "-W 500 is the reply bound: 2 lost probes took $W_MS ms (icmp_echo_ex#100)"
else
    fail "-W 500 × 2 lost probes took $W_MS ms; expected ~1000 (#55's fixed bound is ~3000 each)"
fi
if segment "$CMD3" | grep -qaE 'echo timeout ms *: 500$'; then
    pass "--diag names the bound #100 was given (500 ms)"
else
    fail "--diag has no 'echo timeout ms: 500' line"
fi
if segment "$CMD3" | grep -qaE 'icmp tx *: 2 this run \([0-9]+ since boot\)'; then
    pass "--diag: icmp tx moved by exactly this run's 2 requests"
else
    fail "--diag: no 'icmp tx: 2 this run (N since boot)' line"
fi
if segment "$CMD3" | grep -qaE 'icmp rx *: 0 this run'; then
    pass "--diag: icmp rx did not move"
else
    fail "--diag: no 'icmp rx: 0 this run' line"
fi
if segment "$CMD3" | grep -qa 'verdict *: requests left this host and no reply matched'; then
    pass "--diag verdict: sent, nothing came back — a network fault, not a local one"
else
    fail "--diag gave no 'requests left this host' verdict"
fi

# SIGINT in the interval sleep: seen within a slice, and yo still summarises.
S_MS="$(ys_field "$CMD4" ms)"
S_KILL="$(ys_field "$CMD4" kill)"
S_EXIT="$(ys_field "$CMD4" exit)"
S_SENT="$(segment "$CMD4" | sed -n 's/^\([0-9][0-9]*\) sent .*% loss.*/\1/p' | head -1)"
if [ -z "$S_MS" ]; then
    fail "SIGINT run (sleep): no yosmoke line — yo did not stop within the wait"
elif [ "$S_KILL" != "0" ]; then
    fail "SIGINT run (sleep): kill#16 answered $S_KILL"
elif [ "$S_MS" -lt 400 ]; then
    pass "SIGINT in the interval sleep ended yo in $S_MS ms (sliced sleep)"
else
    fail "SIGINT in the interval sleep took $S_MS ms to end yo; expected < 400 (one 50 ms slice)"
fi
if [ -n "$S_SENT" ] && [ "$S_SENT" -ge 1 ] && [ "$S_SENT" -lt 30 ]; then
    pass "the interrupted run printed its summary: $S_SENT of 30 sent"
else
    fail "the interrupted run printed no summary with fewer than 30 sent (got '${S_SENT}')"
fi
if [ -n "$S_EXIT" ] && [ "$S_EXIT" -lt 256 ]; then
    pass "yo exited normally after SIGINT (status $S_EXIT), not by the signal"
else
    fail "yo's wait status after SIGINT was '${S_EXIT}'"
fi

# SIGINT during the last probe's reply wait, with a second target queued.
L_MS="$(ys_field "$CMD5" ms)"
if [ -z "$L_MS" ]; then
    fail "SIGINT run (reply wait): no yosmoke line"
else
    if segment "$CMD5" | grep -qa "^yo $TARGET — 41 bytes"; then
        fail "SIGINT during the last reply wait: the second target started anyway"
    else
        pass "SIGINT during the last reply wait: the run stopped before the second target"
    fi
    if segment "$CMD5" | grep -qaE "^1 sent .* 100% loss"; then
        pass "the first target's probe finished and was summarised"
    else
        fail "no '1 sent · 0 received · 100% loss' summary for the first target"
    fi
    # Informational: agnos does not wake the echo for an ordinary signal, so the
    # wait runs to -W (2000 ms from the start; ~1300 ms after a signal at 700).
    if [ "$L_MS" -lt 1000 ]; then
        echo "  INFO: the reply wait ended ${L_MS} ms after SIGINT, before -W. Either -W did not"
        echo "        reach the echo (see the -W run above), or agnos now interrupts the echo on a"
        echo "        signal, and platform_wait_readable's note is stale."
    else
        echo "  INFO: the reply wait ran to -W, ${L_MS} ms after SIGINT (no ring-3 way to cut it short)"
    fi
fi

echo ""
echo "  serial log: $LOG"
if [ "$rc" -eq 0 ]; then echo "agnos-qemu-smoke: PASS"; else echo "agnos-qemu-smoke: FAIL"; fi
exit $rc
