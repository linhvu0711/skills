# The plan page

The plan has two forms. The `.md` file, in the shape of `plan.md`, is
the plan: `/handoff` reads it. The `.html` page is the same plan
rendered for review in a browser. Chat carries neither, only the URL and
a short summary.

## Files

Folder: `$HOME/.agents/artifacts/plan/`. Create it when
needed. Slug: `<owner>-<repo>-<n>`, the first ticket's number; a run
adds `-run`. A chat plan has no number: `<owner>-<repo>-chat-<words>`,
two to four words of its title, lower case, joined by `-`. The words
also name its branch, `<type>/<words>`. So when the plan is first
written, both must be free: no `plan-<slug>.md` in the folder, and no
branch `<type>/<words>` in `git branch --list` or
`git ls-remote --heads origin`. One is taken: add `-2`, then `-3`, and
so on to the words, until both are free. An edit to the plan keeps its
slug.

- `plan-<slug>.md`: the plan, verbatim per `plan.md`.
- `plan-<slug>.html`: what `../skills/plan-up/scripts/build-page.py` writes from the `.md`.

The folder holds `plan-<slug>.md`, `plan-<slug>.html`, and `/ship`'s
`prompt-<slug>.md`. The `.md` keeps
its `Repo: owner/repo` line in Facts: `../skills/plan-up/scripts/prune.sh` reads it to
know when the plan's issues are closed and its files can go. A chat
plan's files go 30 days after its `.md` last changed.

## Build

```sh
python3 ../skills/plan-up/scripts/build-page.py "$DIR/plan-<slug>.md"
```

It writes `plan-<slug>.html` and prints `page: <path>`. Problem lines
name the block to fix in the `.md`; fix it and run the builder again.
Never write `DATA` or edit the `.html`: the builder makes it.

Refs the page shows, and the user names in chat: `M1` map part 1, `P1`
proved 1, `S2` slice 2, `S2.T1` its first test, `W1` walk 1, `V1` video 1, `D3` decided 3, `O1` out of
scope 1, `#4` Proof row 4. An edit request names one of these; change
the `.md` line, rebuild.

## Serve, open

Serve with the script, which prints the page URL; the review path is
that URL, not `file://`.

```sh
URL=$(../skills/plan-up/scripts/serve.sh "$DIR" "plan-<slug>.html")
```

It reuses a server only when that server gives back this exact file.
A server on 8765 that holds another folder is left running, and the
page gets the next free port. Never start `http.server` by hand: a
port that is only in use is not a port that serves this folder, and the
person gets a 404. Run the script again after every rebuild; the port
can differ between plans, so use the URL it prints.

**The review**, in the person's own browser: `open "<url>"` on macOS,
`xdg-open "<url>"` on Linux, with `"$URL?v=<n>"`, after the build
prints `page:`. This is the step the person sees. Run it on the first
build and after every rebuild.
Bump `v` on every rebuild, or the browser shows the old page. Leave the
page open. Do not open the page with browser tools: `shell.html` is
fixed, and a render bug in it gets fixed there, once, not worked around
in the plan.

## Headless host

`command -v open xdg-open` finds neither: there is no browser to leave
the page in. Build and serve as above, then publish the `.html` with the
`to-artifact` skill. The first round is a first publish; every rebuild
republishes to the same artifact, so the link never changes and an open
view refreshes on its own. In chat the artifact link takes the place of
the local URL. Publish fails: say why, give the `.html` path, stop.

## Chat

After the page is open, chat gets this and nothing more:

```
Plan: #42 Export orders as CSV · size/M · base main
6 done-when · 6 slices · 1 doc · 1 probe · 3 walks · 2 videos · 1 fork answered (A, stream)
http://127.0.0.1:8765/plan-acme-shop-42.html
$HOME/.agents/artifacts/plan/plan-acme-shop-42.md
Say ok, or name a ref (S2, W1, D3, #4) and what to change.
```

A run: one line per layer under the first. A chat plan: its first line
has no `#<n>`, as in
`Plan: [feat] Export orders as CSV · size/M · base main`. A
`handoff-ready` ticket adds `· short path` after the size, so the user
knows the Steps were trusted. `doc` counts `Docs` lines and `probe` counts `Proved` lines;
each drops when it is 0. The whole plan never goes in chat.
