# embed-source

Puts a library's full source next to your repo, at the exact version you install, so coding agents read real code and tests instead of guessing from docs.

## Use it when

- `/embed-source effect` or "add zod for the agent to read": embed a library.
- `/embed-source update effect`: move it to the version you now install.
- `/embed-source check` or "is our embedded effect source stale?": a read-only status table.

Effect has a preset. Any other library works too; the skill asks for its repo URL, package name, and tag format.

## What you get

- `repos/<lib>/`, a shallow clone at the tag that matches your installed version. Git ignores it, and so do your editor, TypeScript, linter, and test runner.
- A `postinstall` hook, so every `pnpm install` (or npm, yarn) fetches the source for the whole team.
- Short idiom files in `docs/idioms/`, each snippet quoted from the library's own tests with its path.
- A block in `CLAUDE.md` (or `AGENTS.md`) that points agents at all of it, and a section in `README.md` for people without the skill.
- One commit with all of the above. Tests, lint, and type-check pass as before.

`check` prints one line per library:

```
lib=effect prefix=repos/effect synced=yes embedded=3.14.2 installed=3.14.2 ref=effect@3.14.2 readme=3.14.2 drift=no
```

## Needs

- `git`, `bash`, and `node`.
- A JavaScript package manager: pnpm, npm, or yarn. The skill reads versions from `node_modules`.
- The `semble` CLI, to index the new source for search.

## Fits with

- [semantic-code-search](../semantic-code-search/) searches the embedded source with `semble`; this skill warms that index after each add.
