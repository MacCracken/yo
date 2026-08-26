# Getting started with yo

## Build

```sh
cyrius deps                              # resolve dependencies
cyrius build src/main.cyr build/yo    # compile
cyrius test                              # run [build].test + tests/*.tcyr
```

## Layout

- `src/main.cyr` — entry point. Top-level `var r = main(); sys_exit_group(r);` — `sys_exit_group`, not a hardcoded `syscall(SYS_EXIT, ...)`: the exit number differs per target (60 on x86_64, 93 on aarch64), and `exit(2)` ends only the calling thread. Changed in 0.5.9.
- `src/test.cyr` — top-level test entry referenced by `cyrius.cyml [build].test`. Add unit cases here or in `tests/yo.tcyr`.
- `tests/yo.tcyr` — primary test suite (`cyrius test` auto-discovers).
- `tests/yo.bcyr` — benchmarks (`cyrius bench`).
- `tests/yo.fcyr` — fuzz harness (`cyrius fuzz`).

## Adding a feature

1. Edit `src/main.cyr` (or add a new module and `include` it).
2. Add a test case to `tests/yo.tcyr`.
3. Run `cyrius test`.
4. Bump `VERSION` and add a CHANGELOG entry before tagging.

Test entry points must clamp their exit code (`if (r > 0) { r = 1; }`) before
exiting — `assert_summary()` returns the raw failure *count*, and a wait status is
only 8 bits, so exactly 256 / 512 / 768 failures would exit 0 and score PASS.

## Verifying the AGNOS backend

The host build never compiles `src/platform_agnos.cyr`, and `cyrius test` cannot
reach it. Two commands do:

```sh
cyrius build --agnos src/main.cyr build/yo-agnos   # compiles the agnos arm
sh scripts/agnos-qemu-smoke.sh                     # boots agnos in QEMU and probes
```

The smoke needs sibling checkouts (`../agnos`, `../gnoboot`, `../agnoshi`) built, plus
QEMU and OVMF; it SKIPs cleanly rather than failing when they are absent.

See [`../adr/template.md`](../adr/template.md) when a non-trivial design choice deserves an ADR.
