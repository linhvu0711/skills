---
name: embed-source
description: "Embed a dependency's full source next to the repo (fetched on install, never tracked by git) so coding agents can read real implementations and tests, then wire excludes, a CLAUDE.md block, a README section, and idiom files. Use for /embed-source <lib>, /embed-source update <lib>, /embed-source check, 'vendor the effect source', 'add <lib> for the agent to read', or 'is our embedded effect source stale'. Effect has a preset; any other library works with a repo URL."
argument-hint: "<lib> | update <lib> | check"
---

Paths in this skill are relative to its folder, the one that holds this `SKILL.md`. Before you run or read one of them, put that folder's absolute path in front of it.

Agents read code well and docs badly, and a library's tests show the shapes its docs only describe. This skill shallow-clones a library into `repos/<lib>` at the tag that matches the version the project installs, keeps it out of git and out of the toolchain, and writes short idiom files that quote the shapes the project uses. Every step is safe to run twice. The manifest, file headers, and marker comments carry the state; there is no state file to drift.

Modes: `add` (default), `update <lib>`, `check`. Read the preset `presets/<lib>.md` when one exists. No preset: ask for the repo URL, the npm package name, the path of that package's `package.json` inside the repo, and the tag format; the tag defaults to `v{version}` and the file to `package.json`.

The layout the skill keeps:

```
repos/README.md            manifest, tracked: one row per lib (lib, package, repo, ref, version_file)
repos/<lib>/               the fetched source, ignored by git, with a .embed-source-ref marker
scripts/sync-repos.sh      reads the manifest and fetches every lib; run by postinstall
docs/idioms/<lib>-*.md     idiom files, each with an `embed-source: <lib>@<version>` header
CLAUDE.md                  one block between embed-source:start / end markers
README.md                  one section between the same markers, for people without this skill
```

## check

Run `scripts/status.sh <repo-root>`. It prints one line per embedded lib: synced or not, embedded version, installed version, idiom-file versions, README section version, and `drift=yes|no`. Report the table and stop. This mode is read-only, so run it freely after any dependency bump.

## add <lib>

1. **Status first.** Run `scripts/status.sh`. The lib is listed with `drift=no`: say so and stop. `drift=yes`: switch to update mode. `repos/<lib>` exists with no `.embed-source-ref` marker: someone copied files by hand; report it and stop.
2. **Preflight.** A git repo with a clean work tree. The package installed: look in `node_modules/<package>`, the pnpm store, and workspace `node_modules`, and install it first when it is absent. The point is to match the installed version.
3. **Resolve the ref.** Fill `{version}` in the preset's `ref` with the installed version. Confirm the tag with `git ls-remote --tags <repo> "refs/tags/<ref>"`. No such tag: take the nearest lower tag. The ref is always a tag, never `main`: an agent that reads next month's API writes code that fails against today's package.
4. **Confirm.** Show the ref, the size of the clone, and that a `postinstall` script goes into the root `package.json` so `pnpm install` (or npm, yarn) fetches the source for everyone. Wait for a yes.
5. **Manifest and ignore.** Create `repos/README.md` from `templates/repos-readme.md` when missing, and append the lib's row. Add to `.gitignore`, each line only when missing:
   ```
   repos/*
   !repos/README.md
   ```
6. **Sync script.** Copy `templates/sync-repos.sh` to `scripts/sync-repos.sh` when missing and make it executable. Add `"postinstall": "bash scripts/sync-repos.sh"` to the root `package.json` when it has no postinstall; when it has one, append `&& bash scripts/sync-repos.sh`. Run the script. Report `du -sh repos/<lib>`.
7. **Hide it from the toolchain.** Merge into each file, adding each entry only when missing. The pattern is `repos/**` unless the tool wants a folder form.
   - `.vscode/settings.json`: `files.exclude`, `files.watcherExclude`, `search.exclude`, `typescript.preferences.autoImportFileExcludePatterns`, `javascript.preferences.autoImportFileExcludePatterns`.
   - `tsconfig.json` (and any `tsconfig.*.json` with an `include`): `exclude`. A tsconfig whose `include` is only `src` needs nothing.
   - Lint and format: eslint flat config `ignores`, or `.eslintignore`; `biome.json` `files.includes` gets `"!!repos"`; `.prettierignore`.
   - Test runner: vitest or jest `exclude`, when a config file exists.
   Touch only config files the project already has.
8. **CLAUDE.md block.** Render `templates/agents-block.md`, one table row per embedded lib. Replace the text between the `embed-source:start` and `embed-source:end` markers when they exist; append the block when they do not. Prefer `CLAUDE.md`; use `AGENTS.md` when only that exists; create `CLAUDE.md` when neither does.
9. **README section.** Render `templates/readme-section.md` into the project `README.md` between the same markers, replacing or appending as in step 8. No `README.md`: create one with just that section. It is for a person with no skills installed, so it says what the folders are, the three rules, and the plain commands.
10. **Idiom files.** Write the files the preset names, from `templates/idiom-file.md`. Every snippet comes from a test or source file under `repos/<lib>`, with its path in a comment above it. Set the header to the embedded version. In add mode an existing idiom file stays as it is; a human may have tuned it.
11. **Warm search.** Run one `semble search "<any query>" repos/<lib> -k 1`, so the index covers the new files before the next agent needs it.
12. **Verify and commit.** Type-check, lint, and tests pass exactly as they did before the add; a new failure means an exclude is missing. `git status` lists nothing under `repos/` but the manifest. Commit the manifest, ignore, script, package.json, config, CLAUDE.md, README, and idiom files as one commit. Report the commit subject and the size on disk.

## update <lib>

1. Run `scripts/status.sh`. Embedded equals installed and no idiom file or README section lags: say "already at <version>" and stop.
2. Resolve and confirm the ref as in add. Change the ref column in `repos/README.md`, run `scripts/sync-repos.sh`, and change the version in the CLAUDE.md block and the README section.
3. For each idiom file whose header lags, open every snippet's source path in the new tree. The code still matches: bump the header only. It changed: rewrite that snippet from the new test and say what changed. Ask before you rewrite a file a human edited (git blame shows a commit not made by this skill).
4. Verify and commit as in add.

## Done means

`scripts/status.sh` prints `drift=no` for the lib; type-check, lint, and tests pass; `repos/<lib>` is not tracked; and the CLAUDE.md block, README section, manifest row, and idiom-file headers all show the same version.
