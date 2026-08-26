# Architecture Decision Records

Decisions about yo — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** If a decision supersedes a prior one, add a new ADR and set the old one's status to `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## ADR vs. architecture note vs. guide

| Kind | Lives in | Answers |
|---|---|---|
| ADR | `docs/adr/` | *Why did we choose X over Y?* |
| Architecture note | `docs/architecture/` | *What non-obvious constraint is true about the code?* |
| Guide | `docs/guides/` | *How do I do X?* |

## Index

| ADR | Status | Decision |
|---|---|---|
| [0001](0001-per-backend-sovereignty.md) — Per-backend sovereignty | Accepted | Linux uses the host's POSIX socket surface pragmatically; the AGNOS backend uses sovereign kernel syscalls only. Sovereignty is enforced **per backend**, not project-wide. |
| [0002](0002-focused-kernel-icmp-syscall.md) — Focused kernel ICMP syscall | Accepted | agnos exposes one-shot `icmp_echo(dst) → rtt_ms` rather than a general send/recv surface, and yo adapts to that shape. Costs `-W` and real TTL on that backend. |
