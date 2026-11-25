---
status: amends ADR-0016
---

# One find-all call finds every harness's sessions

This amends ADR 0016. Retro, recall, and why find past sessions through one command, `shared/sessions/find_all.py`. It runs each installed adapter's find once, and reports each harness's installed state and the harness data that has no adapter. Adapters keep find and extract, and lose probe. Probe ran the whole finder only to count rows, so every search ran each finder twice, and three skills repeated the scan-then-find steps by hand. The three finders share one rule for roots and the day window, the `Scope` in `adapter_lib.py`. The rest of ADR 0016 holds: one adapter per harness, a new harness is a new folder, harness data with no adapter is reported, and the one-tool skills call their tool's scripts directly.
