<!-- embed-source:start -->
## Embedded library source

Full source of some dependencies lives under `repos/`. Read the real implementations and tests there instead of guessing from docs.

| lib | version | idiom files |
| --- | --- | --- |
| {lib} | {version} | `docs/idioms/{lib}-*.md` |

- `repos/` is read-only reference, outside the build and outside git. Edits there are lost on the next fetch.
- Import from the installed package, never from `repos/`.
- Start with the idiom files. They quote the shapes this project uses. Search the source with `semble search "<what it does>" repos/{lib} -k 5` when the idiom files do not cover a case.
- Missing `repos/{lib}`? Run `bash scripts/sync-repos.sh`.
- Update with `/embed-source update {lib}` after bumping the package. Check drift with `/embed-source check`.
<!-- embed-source:end -->
