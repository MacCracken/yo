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
# between them. This is that gate: the last open item in roadmap.md § 0.6.x.
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
COUNT="${YO_SMOKE_COUNT:-2}"
PROMPT="${YO_SMOKE_PROMPT:-\[ASSIST\] >}"
BOOT_TIMEOUT="${YO_SMOKE_BOOT_TIMEOUT:-120}"
RUN_TIMEOUT="${YO_SMOKE_RUN_TIMEOUT:-90}"

rc=0
skip() { echo "SKIP: $*"; exit 0; }
fail() { echo "  FAIL: $*"; rc=1; }
pass() { echo "  PASS: $*"; }

for tool in qemu-system-x86_64 parted mformat mmd mcopy sgdisk mkfs.ext2 dd tr python3; do
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

# Can the host forward guest ICMP at all? See SLIRP NOTE.
PGR="$(cat /proc/sys/net/ipv4/ping_group_range 2>/dev/null || echo '1 0')"
PGR_LO="$(echo "$PGR" | awk '{print $1}')"
PGR_HI="$(echo "$PGR" | awk '{print $2}')"
MYGID="$(id -g)"
SLIRP_ICMP=1
if [ "$MYGID" -lt "$PGR_LO" ] || [ "$MYGID" -gt "$PGR_HI" ]; then SLIRP_ICMP=0; fi

echo "  agnos kernel : $AGNOS_KERNEL ($(stat -c%s "$AGNOS_KERNEL") B)"
echo "  yo (agnos)   : $YO_BIN ($(stat -c%s "$YO_BIN") B)"
echo "  target       : $TARGET (count=$COUNT)"
echo "  host ICMP    : gid=$MYGID vs ping_group_range='$PGR' -> slirp_icmp=$SLIRP_ICMP"
echo ""

WORK="$ROOT/build/agnos-smoke"
rm -rf "$WORK"; mkdir -p "$WORK"
IMG="$WORK/agnos-yo.img"
SEED="$WORK/seed"; mkdir -p "$SEED/bin"
cp "$AGNSH"  "$SEED/bin/agnsh"
cp "$YO_BIN" "$SEED/bin/yo"
chmod +x "$SEED/bin/agnsh" "$SEED/bin/yo"

PART_OFFSET=$(( 33 * 1048576 ))
PART_BYTES=$(( 67 * 1048576 ))
PART_BLOCKS=$(( PART_BYTES / 4096 ))
# Conservative feature set — agnos's ext2 driver implements none of
# metadata_csum / 64bit / dir_index. Same list its own smokes use.
EXT2_FEATURES="${EXT2_SMOKE_FEATURES:-^resize_inode,^dir_index,^metadata_csum,^64bit,^uninit_bg}"

dd if=/dev/zero of="$IMG" bs=1M count=128 status=none
parted -s "$IMG" mklabel gpt \
    mkpart ESP fat32 1MiB 33MiB set 1 esp on \
    mkpart agnos-fs ext2 33MiB 100MiB
sgdisk -t 2:8300 "$IMG" >/dev/null
mformat -i "$IMG"@@1048576 -F
mmd -i "$IMG"@@1048576 ::EFI ::EFI/BOOT ::boot
mcopy -i "$IMG"@@1048576 "$GNOBOOT" ::EFI/BOOT/BOOTX64.EFI
mcopy -i "$IMG"@@1048576 "$AGNOS_KERNEL" ::boot/agnos
mkfs.ext2 -F -q -L AGNOS-YO -b 4096 -m 0 -O "$EXT2_FEATURES" \
    -d "$SEED" -E offset=$PART_OFFSET "$IMG" $PART_BLOCKS

cp "$OVMF_VARS_SRC" "$WORK/vars.fd"; chmod +w "$WORK/vars.fd"

LOG="$WORK/serial.log"
QMP="$WORK/qmp.sock"
: > "$LOG"
rm -f "$QMP"

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
    >/dev/null 2>&1 &
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
    python3 - "$QMP" "$1" <<'PY'
import json, socket, sys, time

sock_path, line = sys.argv[1], sys.argv[2]

QCODE = {
    ' ': 'spc', '-': 'minus', '.': 'dot', '/': 'slash', ',': 'comma',
    '=': 'equal', ':': 'shift+semicolon', '_': 'shift+minus',
}
for c in 'abcdefghijklmnopqrstuvwxyz0123456789':
    QCODE[c] = c

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

cleanup; trap - EXIT

echo ""
echo "  --- yo output ---"
logtext | sed -n "/^yo $TARGET/,/% loss/p" | sed 's/^/  /'
logtext | grep -a -A 10 -- '--- diag:' | sed 's/^/  /'
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

LOSS_LINE="$(logtext | grep -a '% loss' | head -1)"
# ⛔ ANCHOR THIS. `grep '0% loss'` also matches "10*0% loss*" — an unanchored
# match reported PASS on a 100%-loss run, which is the one result this gate
# exists to catch. Require a non-digit (or start of line) before the 0.
if echo "$LOSS_LINE" | grep -qaE '(^|[^0-9])0% loss'; then
    pass "0% loss — icmp_echo#55 round-tripped: $LOSS_LINE"
else
    if [ "$SLIRP_ICMP" -eq 1 ]; then
        fail "replies expected (this host CAN forward guest ICMP) but got: ${LOSS_LINE:-<none>}"
    else
        echo "  INFO: no replies, and this host cannot forward guest ICMP"
        echo "        (gid $MYGID outside ping_group_range '$PGR') — reply gate not asserted."
        echo "        Widen with: sysctl -w net.ipv4.ping_group_range='0 2147483647'"
    fi
fi

echo ""
echo "  serial log: $LOG"
if [ "$rc" -eq 0 ]; then echo "agnos-qemu-smoke: PASS"; else echo "agnos-qemu-smoke: FAIL"; fi
exit $rc
