# The plan page

The plan has two forms. The `.md` file, in the shape of `plan.md`, is
the plan: `/handoff-devin` reads it. The `.html` page is the same plan
rendered for review in a browser. Chat carries neither, only the URL and
a short summary.

## Files

Folder: `$HOME/.agents/artifacts/plan/`. Create it when
needed. Slug: `<owner>-<repo>-<n>`, the first ticket's number; a run
adds `-run`.

- `plan-<slug>.md`: the plan, verbatim per `plan.md`.
- `plan-<slug>.html`: `assets/shell.html` with `DATA` filled.

The folder holds only `plan-<slug>.*` and `/ship`'s `prompt-<slug>.md`.
A script or draft you write to build the page goes in a temp folder
(the session scratchpad, or `mktemp -d`), never here. The `.md` keeps
its `Repo: owner/repo` line in Facts: `scripts/prune.sh` reads it to
know when the plan's issues are closed and its files can go.

## DATA

`shell.html` renders one object. Fill it from the `.md` you wrote, block
by block; the same facts, structured. Inline markup inside any string:
`` `path:line` `` becomes a copy chip, `**bold**` is bold.

```js
const DATA = {
  title: "<issue title>",
  issue: { number: 42, url: "<issue url>", size: "size/M", kind: "feat" },
  date: "YYYY-MM-DD",
  facts: { repo, base, test, typecheck, lint, build, run, ui, open, screen, platform, standards },
  points: "Points: 6 (XS 1, S 2, M 4, L 8)",                        // runs only
  layers: [ /* one per ticket; a single ticket is one layer */
    {
      issue: { number, url, size },
      title: "<ticket title>",
      targets: "<base or lower layer branch>", points: 4,         // runs only, from the Stack table
      summary: "2 to 3 lines: what changes, the path slice 1 takes, the counts.",
      forks: [ { question, pick, why } ],           // big forks the user answered
      seams: [ { name, at: "path:line", why } ],
      proof: [ { line, test: { file, name } | null, walk: 1 | null, video: "video 1 @ step 4" | null, artifact: "test" | "screenshot 1" } ],
      slices: [ { seam, proves: [1, 2], change: ["`path:line`, what. Copy the shape of `path:line`."],
                  tests: [ { file, name, given, when, then } ] } ],
      walks: [ { title, proves: [1], setup, where, steps: ["..."], see, mustNot } ],
      videos: [ { title, setup: "walk 1", walks: [1, 3], steps: ["..."], shows: "#1 at step 4" } ],
      gates: { slice, task, untouched: ["file \"case\""] },
      decided: [ { what, why, at: "path:line" } ],
      out: ["..."]
    }
  ]
};
```

Refs the page shows, and the user names in chat: `S2` slice 2, `S2.T1`
its first test, `W1` walk 1, `V1` video 1, `D3` decided 3, `O1` out of
scope 1, `#4` Proof row 4. An edit request names one of these; change
the `.md` line and the `DATA` field, rebuild.

## Build, serve, open

Build: copy the shell and replace its empty `DATA`.

```sh
python3 - "$JSON" ~/.agents/skills/plan-up/assets/shell.html "$OUT" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1])); shell = open(sys.argv[2]).read()
open(sys.argv[3], 'w').write(shell.replace('const DATA = {};', 'const DATA = ' + json.dumps(data, ensure_ascii=False, indent=1) + ';'))
EOF
```

`$JSON` is the `DATA` object saved as `plan-<slug>.json` in the same
folder, so a rebuild after an edit is one command.

Serve with `scripts/serve.sh`, in this skill's folder. It prints the
page URL. `file://` is not the review path.

```sh
URL=$(scripts/serve.sh "$DIR" "plan-<slug>.html")
```

It reuses a server only when that server gives back this exact file.
A server on 8765 that holds another folder is left running, and the
page gets the next free port. Never start `http.server` by hand: a
port that is only in use is not a port that serves this folder, and the
person gets a 404. Run the script again after every rebuild; the port
can differ between plans, so use the URL it prints.

Then, in this order:

1. **The check**, a script, not a browser: it reads the `DATA` the page
   embeds and compares it with the `.md`.

   ```sh
   python3 ~/.agents/skills/plan-up/scripts/check-page.py "$OUT" "$DIR/plan-<slug>.md"
   ```

   It prints `page ok` or one line per problem: a count that differs
   from the `.md`, `[object`, or a string with an odd number of
   backticks. Fix the `DATA`, rebuild, run it again.
2. **The review**, in the person's own browser: `open "<url>"` on macOS,
   `xdg-open "<url>"` on Linux, with `"$URL?v=<n>"`, after the check
   passes. This is the step the person sees. Run it on the first build
   and after every rebuild, with the new `v`.

Bump `v` on every rebuild, or the browser shows the old page. Leave the
page open. Do not open the page with browser tools: `shell.html` is
fixed, and a render bug in it gets fixed there, once, not worked around
in `DATA`.

## Headless host

`command -v open xdg-open` finds neither: there is no browser to leave
the page in. Serve and check as above, then publish the `.html` with the
`to-artifact` skill. The first round is a first publish; every rebuild
republishes to the same artifact, so the link never changes and an open
view refreshes on its own. In chat the artifact link takes the place of
the local URL. Publish fails: say why, give the `.html` path, stop.

## Chat

After the page is open, chat gets this and nothing more:

```
Plan: #42 Export orders as CSV · size/M · base main
6 done-when · 6 slices · 3 walks · 2 videos · 1 fork answered (A, stream)
http://127.0.0.1:8765/plan-acme-shop-42.html
~/.agents/artifacts/plan/plan-acme-shop-42.md
Say ok, or name a ref (S2, W1, D3, #4) and what to change.
```

A run: one line per layer under the first. A `handoff-ready` ticket
adds `· short path` after the size, so the user knows the Steps were
trusted. The whole plan never goes in chat.
