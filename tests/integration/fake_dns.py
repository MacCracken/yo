"""Fake DNS server for tests/integration/run.sh (stdlib only; run with python3 -I).

Listens on --listen:53 and answers a fixed zone:
  PTR 1.0.0.127.in-addr.arpa  -> a name whose label carries ESC sequences (audit C)
  PTR 1.9.9.10.in-addr.arpa   -> gw.test
  A   plain.test              -> 127.0.0.1
  A   forge.test              -> first a FORGED answer (10.6.6.6) sent from a
                                 different source port, then the real one
                                 (127.0.0.1) from :53 (audit K)
  anything else               -> NXDOMAIN
Also listens on each --trap address:53 and appends one line to --trap-log for
every datagram it gets there, answering nothing: the test reads that log to see
whether yo fell back to a public resolver it should not have used (audit I).
"""
import argparse
import select
import socket
import struct
import sys

ESC_NAME = [b"\x1b[31mevil\x1b[0m", b"test"]


def parse_question(msg):
    """Return (qid, qname_labels, qtype, end_offset) or None."""
    if len(msg) < 12:
        return None
    qid = struct.unpack("!H", msg[:2])[0]
    off = 12
    labels = []
    while off < len(msg):
        n = msg[off]
        if n == 0:
            off += 1
            break
        if n > 63:
            return None
        labels.append(msg[off + 1 : off + 1 + n])
        off += 1 + n
    if off + 4 > len(msg):
        return None
    qtype = struct.unpack("!H", msg[off : off + 2])[0]
    return qid, labels, qtype, off + 4


def encode_name(labels):
    return b"".join(bytes([len(l)]) + l for l in labels) + b"\x00"


def reply(msg, qend, rcode, answers):
    """answers: list of (type, rdata bytes)."""
    hdr = msg[:2] + struct.pack("!HHHHH", 0x8180 | rcode, 1, len(answers), 0, 0)
    body = msg[12:qend]
    for rtype, rdata in answers:
        body += b"\xc0\x0c" + struct.pack("!HHIH", rtype, 1, 60, len(rdata)) + rdata
    return hdr + body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="127.0.0.1")
    ap.add_argument("--trap", action="append", default=[])
    ap.add_argument("--trap-log", default="/dev/null")
    ap.add_argument("--ready", default=None, help="file to create once listening")
    a = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    srv.bind((a.listen, 53))
    forger = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    forger.bind((a.listen, 0))
    traps = []
    for t in a.trap:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind((t, 53))
        traps.append(s)
    if a.ready:
        open(a.ready, "w").close()

    while True:
        ready, _, _ = select.select([srv] + traps, [], [])
        for s in ready:
            msg, peer = s.recvfrom(2048)
            if s is not srv:
                with open(a.trap_log, "a") as f:
                    f.write(f"query to trap {s.getsockname()[0]} from {peer}\n")
                continue
            q = parse_question(msg)
            if q is None:
                continue
            qid, labels, qtype, qend = q
            name = b".".join(labels).lower()
            if qtype == 12 and name == b"1.0.0.127.in-addr.arpa":
                srv.sendto(reply(msg, qend, 0, [(12, encode_name(ESC_NAME))]), peer)
            elif qtype == 12 and name == b"1.9.9.10.in-addr.arpa":
                srv.sendto(reply(msg, qend, 0, [(12, encode_name([b"gw", b"test"]))]), peer)
            elif qtype == 1 and name == b"plain.test":
                srv.sendto(reply(msg, qend, 0, [(1, bytes([127, 0, 0, 1]))]), peer)
            elif qtype == 1 and name == b"forge.test":
                forger.sendto(reply(msg, qend, 0, [(1, bytes([10, 6, 6, 6]))]), peer)
                srv.sendto(reply(msg, qend, 0, [(1, bytes([127, 0, 0, 1]))]), peer)
            else:
                srv.sendto(reply(msg, qend, 3, []), peer)


if __name__ == "__main__":
    sys.exit(main())
