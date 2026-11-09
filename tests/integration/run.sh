#!/usr/bin/env bash
# tests/integration/run.sh — end-to-end checks that need a network namespace.
#
# What the unit suite cannot reach: the SOCK_RAW fallback, real Ctrl-C delivery,
# a multi-target run, RSS over a long run, and DNS end to end. Each check names
# the 0.7.2 audit finding it pins (docs/audit/2026-11-08-audit.md).
#
# Builds yo fresh into build/yo-integration on every run (set YO=<binary> to
# test another build instead, e.g. an older release for a before/after), then
# re-runs itself inside a new network + mount namespace:
#   - `unshare -r -n -m` where unprivileged user namespaces are allowed;
#   - else `sudo -n unshare -n -m` (GitHub's Ubuntu 24.04 runners restrict
#     unprivileged user namespaces through AppArmor).
# Inside, ping_group_range denies SOCK_DGRAM, so yo takes the SOCK_RAW
# fallback; a dummy interface gives a black-hole address (10.9.9.2, fd00::2);
# /etc/resolv.conf is bind-mounted to point at tests/integration/fake_dns.py on
# 127.0.0.1:53, and 1.1.1.1 (yo's fallback resolver) is a trap that logs any
# query it gets.
#
# Exit: 0 all passed, 1 any failed, 77 could not enter a namespace (CI sets
# YO_REQUIRE_NETNS=1 so that is a failure there, not a skip).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

if [ "${YO_IN_NETNS:-0}" != 1 ]; then
    if [ -z "${YO:-}" ]; then
        YO="$ROOT/build/yo-integration"
        mkdir -p "$ROOT/build"
        (cd "$ROOT" && cyrius build src/main.cyr "$YO") >/dev/null 2>&1 || { echo "build failed"; exit 1; }
    fi
    if unshare -r -n -m true 2>/dev/null; then
        exec unshare -r -n -m -- env YO_IN_NETNS=1 YO="$YO" bash "$0"
    elif sudo -n true 2>/dev/null; then
        exec sudo -n unshare -n -m -- env YO_IN_NETNS=1 YO="$YO" PATH="$PATH" bash "$0"
    fi
    echo "SKIP: needs 'unshare -r -n -m' or passwordless sudo"
    if [ "${YO_REQUIRE_NETNS:-0}" = 1 ]; then exit 1; fi
    exit 77
fi

W="$(mktemp -d)"
DNS_PID=""
cleanup() { [ -n "$DNS_PID" ] && kill "$DNS_PID" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
pass=0; fail=0
ok()    { echo "  ok    $1"; pass=$((pass + 1)); }
bad()   { echo "  FAIL  $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
ms_since() { echo $(( ($(date +%s%N) - $1) / 1000000 )); }

# --- the namespace's network ---
ip link set lo up
ip link add d0 type dummy && ip link set d0 up
ip addr add 10.9.9.1/24 dev d0
ip addr add 1.1.1.1/32 dev d0          # yo's fallback resolver address: a trap
ip -6 addr add fd00::1/64 dev d0 nodad

# --- DNS: resolv.conf -> the fake server on 127.0.0.1 ---
printf 'nameserver 127.0.0.1\n' > "$W/resolv.conf"
mount --bind "$W/resolv.conf" /etc/resolv.conf || { echo "cannot bind-mount /etc/resolv.conf"; exit 1; }
python3 -I "$HERE/fake_dns.py" --listen 127.0.0.1 --trap 1.1.1.1 \
    --trap-log "$W/trap.log" --ready "$W/dns.ready" &
DNS_PID=$!
for _ in $(seq 50); do [ -e "$W/dns.ready" ] && break; sleep 0.1; done
[ -e "$W/dns.ready" ] || { echo "fake DNS server did not start"; exit 1; }

echo "yo integration — $("$YO" -h | head -1) — binary: $YO"
echo "ping_group_range: $(tr '\t' ' ' < /proc/sys/net/ipv4/ping_group_range)"

# --- A: the SOCK_RAW fallback ---
out=$("$YO" -q -n -c 1 -W 200 --diag 10.9.9.2 2>&1)
check "A: v4 takes the SOCK_RAW fallback here" grep -q 'SOCK_RAW' <<<"$out"
out=$("$YO" -q -n -c 1 -W 200 --diag fd00::2 2>&1)
check "A/M: --diag names the v6 SOCK_RAW fallback" grep -q 'SOCK_RAW' <<<"$out"
check "A: RAW v4 live host answers" grep -q '2 received' <<<"$("$YO" -q -n -c 2 -i 100 127.0.0.1)"
check "A: RAW v6 live host answers" grep -q '2 received' <<<"$("$YO" -q -n -c 2 -i 100 ::1)"
for fam in 4 6; do
    if [ "$fam" = 4 ]; then live=127.0.0.1; dead=10.9.9.2; else live=::1; dead=fd00::2; fi
    stolen=0
    for _ in 1 2 3; do
        "$YO" -q -n -c 3 -W 500 -i 500 "$live" >/dev/null 2>&1 &
        a=$!
        "$YO" -q -n -c 3 -W 500 -i 500 "$dead" > "$W/b" 2>&1; rb=$?
        wait "$a"
        if [ "$rb" -ne 1 ] || ! grep -q ' 0 received' "$W/b"; then stolen=$((stolen + 1)); fi
    done
    check "A: v$fam dead host stays dead beside a live probe (3 of 3 runs)" [ "$stolen" -eq 0 ]
done

# --- G: sequence numbers past 65535 ---
check "G: 65540 probes, 65540 replies" grep -q '65540 received' <<<"$("$YO" -q -n -c 65540 -i 0 -W 200 127.0.0.1)"

# --- F: no per-probe memory growth ---
"$YO" -q -n -c 100000000 -i 0 127.0.0.1 >/dev/null 2>&1 &
p=$!
sleep 0.5; r1=$(awk '/VmRSS/{print $2}' "/proc/$p/status")
sleep 2;   r2=$(awk '/VmRSS/{print $2}' "/proc/$p/status")
kill "$p"; wait "$p" 2>/dev/null
check "F: RSS flat over 2 s of flood probing (${r1} -> ${r2} KB)" [ $((r2 - r1)) -lt 1024 ]

# --- E: waits end on Ctrl-C, and so does the run ---
out=$("$YO" -W 0 127.0.0.1 2>&1); rc=$?
check "E: -W 0 refused (it meant: wait forever)" [ "$rc" -eq 2 ]
"$YO" -n -c 3 -i 10000 127.0.0.1 > "$W/e1" 2>&1 &
p=$!; sleep 1; t0=$(date +%s%N); kill -INT "$p"; wait "$p"; ms=$(ms_since "$t0")
check "E: Ctrl-C ends a 10 s interval sleep within 1 s (${ms} ms)" [ "$ms" -lt 1000 ]
check "E: ...and the summary still prints" grep -q '1 sent' "$W/e1"
"$YO" -n -c 3 -W 5000 10.9.9.2 > "$W/e2" 2>&1 &
p=$!; sleep 1; t0=$(date +%s%N); kill -INT "$p"; wait "$p"; ms=$(ms_since "$t0")
check "E: Ctrl-C ends a 5 s reply wait within 1 s (${ms} ms)" [ "$ms" -lt 1000 ]
"$YO" -n -c 5 -i 500 127.0.0.1 127.0.0.1 > "$W/e3" 2>&1 &
p=$!; sleep 1; kill -INT "$p"; wait "$p"
check "E: Ctrl-C stops a two-target run after the first target" [ "$(grep -c '^yo ' "$W/e3")" -eq 1 ]

# --- H, L, P, Q: CLI and error paths ---
check "H: -s 70000 refused" [ "$("$YO" -s 70000 127.0.0.1 >/dev/null 2>&1; echo $?)" -eq 2 ]
check "L: an unroutable send says ENETUNREACH, not timeout" grep -q 'ENETUNREACH' <<<"$("$YO" -n -c 1 192.0.2.1 2>&1)"
t0=$(date +%s%N); out=$("$YO" -4 ::1 2>&1); rc=$?; ms=$(ms_since "$t0")
check "P: -4 with an IPv6 literal fails at once, saying why (${ms} ms)" bash -c '[ "$1" -eq 2 ] && [ "$2" -lt 500 ] && grep -q -- "-4 given" <<<"$3"' _ "$rc" "$ms" "$out"
check "P: -6 with an IPv4 literal fails" [ "$("$YO" -6 127.0.0.1 >/dev/null 2>&1; echo $?)" -eq 2 ]
check "Q: --help is all on stdout" [ "$("$YO" -h 2>&1 >/dev/null | wc -c)" -eq 0 ]
check "Q: --help lists every option" [ "$("$YO" -h 2>/dev/null | grep -cE '^ +-')" -ge 11 ]

# --- C, K: what DNS answers are believed ---
out=$("$YO" -c 1 127.0.0.1 2>&1)
check "C: an ESC-laden PTR name never reaches the terminal" bash -c '! grep -q $'"'"'\x1b'"'"' <<<"$1"' _ "$out"
check "C: ...and the banner shows no name for it" grep -qx 'yo 127.0.0.1 — 56 bytes' <<<"$(head -1 <<<"$out")"
check "C: a clean PTR name is still shown" grep -q '(gw.test)' <<<"$("$YO" -c 1 -W 200 10.9.9.1 2>&1)"
check "K: plain.test resolves through the fake server" grep -q '(127.0.0.1)' <<<"$("$YO" -4 -c 1 plain.test 2>&1)"
check "K: a forged answer from another port is ignored" grep -q '(127.0.0.1)' <<<"$("$YO" -4 -c 1 forge.test 2>&1)"

# --- I, N: resolv.conf ---
printf 'nameserver 127.0.0.1\r\n' > "$W/resolv.conf"
check "N: a CRLF resolv.conf works" grep -q '(127.0.0.1)' <<<"$("$YO" -4 -c 1 plain.test 2>&1)"
printf 'nameserver fe80::1\n' > "$W/resolv.conf"
rm -f "$W/trap.log"
out=$("$YO" -4 -c 1 plain.test 2>&1); rc=$?
check "I: only-IPv6 resolvers -> cannot resolve (exit 2)" [ "$rc" -eq 2 ]
check "I: ...and nothing went to the 1.1.1.1 fallback" [ ! -s "$W/trap.log" ]
printf 'search test\n' > "$W/resolv.conf"
"$YO" -4 -c 1 -W 200 plain.test >/dev/null 2>&1
check "I: a resolv.conf naming no server still falls back to 1.1.1.1" [ -s "$W/trap.log" ]

echo "integration: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
