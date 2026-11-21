# TS/JS stack tips

Read this file only when the repo's stack is TypeScript or JavaScript.
Each tip is a default. Step 3's web check confirms it is still current
before it becomes a find, and the repo keeps an old tool only with a
measured reason.

- **Install and scripts**: bun. It replaces npm, yarn, and pnpm. Cache
  the installed packages themselves, seeded from main, so a PR's cache
  hits.
- **Tests**: `bun test`. Test files keep their vitest imports. Isolate
  modules, not processes; reset state after every file; run in random
  order to flush out leaks.
- **Lint**: oxlint, reading the repo's existing lint config, with every
  rule turned on that the code passes or can be fixed to pass. It
  replaces ESLint.
- **Format**: the formatter bun or oxc ships, in place of Prettier.
- **Typecheck**: the native TypeScript compiler (`tsgo`, TypeScript 7)
  in place of `tsc`.
- **Canary**: a tool that exists only in a canary build is pinned to
  that exact build.
- **Database tests**: one throwaway database per test shard.

A swap from one of these tools to another keeps rule 3 of the playbook:
both run side by side first, and the issue lists what the new one
misses.
