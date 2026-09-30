# Third-party notices

Some skills here copy or adapt skills from other repos. This file lists each upstream: what was taken, its license, its full license text, and the upstream commit the copy came from.

- **Copy**: the text is mostly the upstream's, word for word.
- **Heavy adaptation**: the upstream's structure and some of its sentences, rewritten around this repo's skills.

Each copied or adapted skill folder holds its upstream's `LICENSE`. The shared core holds one `LICENSE-<owner>` per upstream. The commit is the one whose files match the first copy in this repo best. Skills that take only an idea, and none of the text, are credited in their README instead.

## juliusbrussee/caveman

- Upstream: https://github.com/juliusbrussee/caveman
- License: MIT
- Commit: `8909f6af8806897cbb8330c11028eee168ad7cc7` (best match of the first copy)

| Skill or file | Upstream path | Level |
|---|---|---|
| `skills/commit` | `skills/caveman-commit` | copy |

The upstream `LICENSE` opens with a scope note: some of its folders are under the Business Source License 1.1. Its `LICENSING.md` puts `skills/` under MIT, so the text below is the MIT part of that file.

### License text

```text
MIT License

Copyright (c) 2026 Julius Brussee

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## poteto/noodle

- Upstream: https://github.com/poteto/noodle
- License: MIT
- Commit: `00ad13458e5aeed004396835d0844b620396d86c` (best match of the first copy)

| Skill or file | Upstream path | Level |
|---|---|---|
| `skills/unslop` | `.agents/skills/unslop` | copy |

### License text

```text
MIT License

Copyright (c) 2026 Lauren Tan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## mattpocock/skills

- Upstream: https://github.com/mattpocock/skills
- License: MIT
- Commit: `321658273cb1d20b76026717d027d505790106d4` (best match of the first copies)

| Skill or file | Upstream path | Level |
|---|---|---|
| `skills/fix-conflicts` | `skills/engineering/resolving-merge-conflicts` | copy |
| `skills/write-for-agents` | `skills/productivity/writing-for-agents` | copy |
| `skills/grill` | `skills/productivity/grilling`, `skills/productivity/grill-me`, `skills/engineering/grill-with-docs`, `skills/engineering/domain-modeling`, `skills/engineering/research` | heavy adaptation (`references/ADR-FORMAT.md` and `references/CONTEXT-FORMAT.md` are copies from `skills/engineering/domain-modeling`) |
| `shared-skill-core/grilling.md` | the same five as `skills/grill` | heavy adaptation |
| `shared-skill-core/facts.md` | the same five as `skills/grill` | heavy adaptation |
| `skills/improve-architecture` | `skills/engineering/improve-codebase-architecture`, `skills/engineering/codebase-design` | heavy adaptation (`references/codebase-design.md`, `references/deepening.md`, and `references/design-it-twice.md` are copies from `skills/engineering/codebase-design`) |
| `skills/triage` | `skills/engineering/diagnosing-bugs` | heavy adaptation |
| `skills/discover-path` | `skills/engineering/wayfinder` | heavy adaptation |
| `skills/to-epic` | `skills/engineering/to-tickets` | heavy adaptation |
| `shared-skill-core/review/general-rules.md` | `skills/engineering/code-review` | heavy adaptation |

### License text

```text
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
