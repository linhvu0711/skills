# build-and-prove

Builds a plan on your machine and proves it with proofbox. Your Mac edits files and runs git; one proofbox Sandbox runs every test, the build, and the app.

## Use it when

You have a plan from [plan-up](../plan-up/) and want it built without the build's load on your Mac. It only runs when you call it.

## What you get

`scripts/box.sh`, which holds the run's one Sandbox: `up` creates it, `run` sends the changed files and runs a command there with its exit code, `down` deletes it. A Sandbox that dies while idle is made again once.

## Needs

- [proofbox](https://github.com/linhvu0711/proofbox), installed and logged in to its Provider.
- A setup script per repo and OS at `~/.agents/proofbox/<owner>-<repo>/setup-<os>.sh`, and an optional `app.env` beside it.

## Fits with

- Builds the plan [plan-up](../plan-up/) writes.
