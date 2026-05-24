# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `src/icmp.cyr` — RFC 792 ICMP echo framing (`icmp_build_echo_request`, type/code/ident/seq/cksum accessors) and RFC 1071 Internet checksum (`icmp_checksum`, `icmp_verify`). Pure code, no syscalls — slots into the kernel ICMP surface when 0.2.x lands.
- `src/cli.cyr` — CLI registry + parse over `lib/flags.cyr`. Owns `-c/-W/-i/-s/-q/-v/-h` (plus matching long forms) and the v0.3.x defaults (count=4, timeout=1000ms, interval=1000ms, size=56). Validation rejects negative ints and missing target.
- `src/main.cyr` — orchestration: parse argv → dispatch help/usage/errors → print planned-probe banner pointing to the pending kernel surface. Exit codes 0/2 per POSIX usage convention. Banner branches on dotted-quad vs hostname target.
- `src/ipv4.cyr` — strict dotted-quad parser. `ipv4_parse(cstr)` returns packed u32 on success (matching `agnos/kernel/core/net.cyr:21` ip4 packing) or `IPV4_PARSE_FAIL` sentinel on any rejection. No hostname/DNS path — that's roadmap 0.3.x.
- `src/stats.cyr` — RTT accumulator + summary formatter. Microsecond integer math (no f64). `stats_record_reply(s, rtt_us)`, `stats_record_loss(s)`, accessors for sent/recv/min/max/avg/loss-pct, `stats_print_summary` matching the README block. Slots into the probe loop when the kernel surface lands.
- `cyrius.cyml [deps].stdlib` += `args`, `flags`.
- `tests/yo.tcyr` — now 79 assertions covering ICMP framing/checksum, CLI defaults / short / long / errors, ipv4 parse happy paths + every rejection class, and stats basics / loss / mixed sequences (incl. README example fixture).

## [0.1.0]

### Added
- Initial project scaffold
