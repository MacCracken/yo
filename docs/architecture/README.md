# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides (those live in [`../guides/`](../guides/)). An item here describes *how the world is*, not *what we chose* or *how to do something*.

## Items

| Note | Invariant |
|---|---|
| [001](001-reply-acceptance-invariants.md) — Reply-acceptance invariants | yo accepts an echo reply on **type alone** — it does not match on ident and does not verify the received checksum in the probe path, even though `src/icmp.cyr` defines `icmp_ident()` and `icmp_verify()`. Each backend has a different reason, and the SOCK_RAW fallback is the weak case. |
