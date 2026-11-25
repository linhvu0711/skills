# HTML report

Copy `assets/report.html` to `$HOME/.agents/artifacts/ci/ci-review-<owner>-<repo>.html` (make the folder when needed), then fill its `{{…}}` placeholders and its empty sections. Keep the head as it is.

## Serve and open

Serve the page with the shared serve script, which prints its URL:

```sh
URL=$(../../shared/serve.sh "$HOME/.agents/artifacts/ci" "ci-review-<owner>-<repo>.html")
```

The script exits with an error (no free port, or the server does not give back the file): chat gets its error line and the `.html` path, and the run stops.

Then open it in the user's browser: `open "$URL?v=$(date +%s)"` on macOS, `xdg-open "$URL?v=$(date +%s)"` on Linux. The `v` makes a rerun on the same repo show the new page, not the cached one. Chat gives `$URL`.

**Headless host** (`command -v open xdg-open` finds neither, or the open command exits with an error): there is no browser to leave the page in. Give no local URL. Publish the page with the `to-artifact` skill and give the artifact link in place of the URL. When the open command failed, chat also gives its error line. Publish fails: say why, give the `.html` path, stop.

## Header

Repo name, the runs read (`112 of 150 runs`, `from` to `to`), the date, and the PR result at p50 and p95. A line under it says when the stack tips were not checked on the web, when the rulesets or the classic branch rules were not read in full, or when there is no run history.

## Timing table

In `<section id="timing">`: one row per job, `w-full text-sm`, with the columns Workflow, Job, Runs, Wait, Setup, Work, Total (each as `p50 / p95`), and Slowest. Sort by Total p95, slowest first. Two workflows that share a name: put each one's `workflow_id` after it, as `CI (21)`. The first CI path leaves the section out.

## Find card

Each big find is one `<article class="card rounded-xl border p-6">`:

- **Title**: names the change, as "Cache the installed packages".
- **Badges**: the goal (`speed` = sky, `honesty` = rose, `security` = amber, `other` = slate), then the run part it moves, when it moves one.
- **Where**: monospaced `path:line` list.
- **Now / Target**: two numbers side by side, as `setup p50 1m50s` and `20s`, with the target's one-line reason under them.
- **Time limit**: the proposed limit for each job the find touches, with the p95 and slowest it comes from.
- **Problem**: one sentence. What it costs, in time or trust.
- **Fix**: one sentence. What changes.
- **Proof**: the evidence label and its source, as `Seen: .github/workflows/ci.yml:41`.

## Small finds

After the cards, in `<section id="small">`: one `<h2>` per group a reader would fix in one sitting ("Pin the actions", "Old runs"), and under it one table, `w-full text-sm`, with the columns What, Where, Goal, and Evidence. No small find: leave the section out.

## Top pick

In `<section id="top-pick">`: the big find to do first and why, in two lines, most often the one with the most time to win; with no big find, the small group to do first.
