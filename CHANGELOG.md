# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `src/icmp.cyr` — RFC 792 ICMP echo framing (`icmp_build_echo_request`, type/code/ident/seq/cksum accessors) and RFC 1071 Internet checksum (`icmp_checksum`, `icmp_verify`). Pure code, no syscalls — slots into the kernel ICMP surface when 0.2.x lands.
- `src/cli.cyr` — CLI registry + parse over `lib/flags.cyr`. Owns `-c/-W/-i/-s/-q/-v/-h` (plus matching long forms) and the v0.3.x defaults (count=4, timeout=1000ms, interval=1000ms, size=56). Validation rejects negative ints and missing target.
- `src/main.cyr` — orchestration: parse argv → dispatch help/usage/errors → print planned-probe banner pointing to the pending kernel surface. Exit codes 0/2 per POSIX usage convention.
- `cyrius.cyml [deps].stdlib` += `args`, `flags`.
- `tests/yo.tcyr` — now 36 assertions covering ICMP framing/checksum plus CLI defaults, short forms, long forms, missing target, negative-value rejection, unknown-flag rejection, and `-h → CLI_HELP`.

## [0.1.0]

### Added
- Initial project scaffold
