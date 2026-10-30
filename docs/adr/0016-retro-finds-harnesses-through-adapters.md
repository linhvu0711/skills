# Retro finds harnesses through their adapters, not a fixed list

Each harness has one adapter in `shared/sessions/<harness>/` with `probe`, `find`, and `extract`. Retro asks every adapter's `probe` whether it holds sessions for this repo and reads those that do. It also reports harness data it finds that has no adapter. The skill text names no harness, so adding one is adding a folder. Letting the agent work out each format at run time was dropped: it is slow, untested, and wrong in new ways each run.
