This machine is the local machine, and the repo's packages are
already installed in the worktree.
Each slice's tests, the typecheck, and lint run here, in the worktree,
with the commands under `Facts`. The full suite, the build, and the app
never run here: after you finish, `/build-and-prove`
runs the Gates in the run's proofbox Sandbox.

A slice's command that fails because this machine lacks a tool
(`command not found`, exit 127): install nothing here. Start the
Sandbox once, then run that command there, every time it runs:

```bash
bash {{skills}}/build-and-prove/scripts/box.sh up <Proof folder> <Worktree> <os> <Repo>
bash {{skills}}/build-and-prove/scripts/box.sh run <Proof folder> -- <command>
```

`<Proof folder>`, `<Worktree>`, and `<Repo>` are the lines of those
names at the top of the prompt; `<os>` is `macos` when `Facts` say
`Platform: macos-outpost`, else `linux`. `run` sends the files you
changed, runs the command there, and exits with the command's code, so
a red test is a non-zero exit. The Sandbox stays for the rest of the
run: never run `box.sh down`. A `stop:` line from it: stop and ask (see
Asking below), say what it printed.

A repo with e2e tests, ones that start the app and drive it in a
browser (a Playwright or Cypress config, an `e2e` script): before each
slice's commit, run the e2e spec files the slice changes, and those
that open a screen or route the slice changes, found by a search of the
e2e folder for that route, page, or component name. They need the app, so they run in
the Sandbox: `box.sh up` once, as above, then `box.sh run <Proof
folder> -- <the repo's e2e command> <spec files>`. Red: the slice is
not green, as with its own test. None found: say so in one line, and
commit.
