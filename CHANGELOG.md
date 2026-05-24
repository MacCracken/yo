# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `src/icmp.cyr` — RFC 792 ICMP echo framing (`icmp_build_echo_request`, type/code/ident/seq/cksum accessors) and RFC 1071 Internet checksum (`icmp_checksum`, `icmp_verify`). Pure code, no syscalls — slots into the kernel ICMP surface when 0.2.x lands.
- `tests/yo.tcyr` — 15 assertions covering the RFC 1071 worked example, build/parse round-trip, tampered-packet rejection, odd-length/empty payload, and too-short-buffer guard.

## [0.1.0]

### Added
- Initial project scaffold
