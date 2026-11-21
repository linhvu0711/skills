#!/usr/bin/env python3
"""Time a repo's GitHub Actions runs: how long each job waits for a machine,
and how long its setup, its work, each step, and the whole job take.

    ci-times.py <owner/repo> [--runs N] [--setup <step name>]...

Reads the last N completed runs (default 150) with `gh`, then each run's
jobs. Prints one JSON object:

    {"repo", "asked", "runs", "from", "to",
     "jobs": [{"workflow", "job", "runs", "wait": {"p50", "p95"},
               "setup": {"p50", "p95"}, "work": {"p50", "p95"},
               "total": {"p50", "p95"}, "slowest",
               "steps": [{"name", "p50", "p95"}]}]}

Times are whole seconds. A job's wait is its start minus its creation, the
time it sat in the queue for a machine. Setup is the sum of a run's setup
steps: `Set up job`, `Complete job`, a step whose name starts with `Post `,
`Run actions/checkout`, `Run actions/setup-`, or `Run actions/cache`, and
each step a `--setup` names. Work is the job's total minus its setup, taken
per run before any percentile, since percentiles do not add. A percentile
is nearest rank, so each one is a real run's time. Skipped and cancelled
jobs and skipped steps are left out. With no runs, `runs` is 0 and `jobs`
is [].

A gh call that fails stops with `stop: gh could not <what>: <gh's last
line>` on stderr and exit 1.
"""

import argparse
import datetime as dt
import json
import math
import subprocess
import sys

RUN_FIELDS = "databaseId,attempt,createdAt,updatedAt,event,headSha,workflowName,conclusion"
LEFT_OUT = {"skipped", "cancelled"}
SETUP_NAMES = {"Set up job", "Complete job"}
SETUP_STARTS = ("Post ", "Run actions/checkout", "Run actions/setup-", "Run actions/cache")


def gh(what, *args):
    done = subprocess.run(["gh", *args], capture_output=True, text=True)
    if done.returncode != 0:
        lines = done.stderr.strip().splitlines() or ["no output"]
        print(f"stop: gh could not {what}: {lines[-1]}", file=sys.stderr)
        sys.exit(1)
    return json.loads(done.stdout or "null")


def when(stamp):
    return dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))


def seconds(start, end):
    return int((when(end) - when(start)).total_seconds())


def rank(values, p):
    ordered = sorted(values)
    return ordered[max(math.ceil(p / 100 * len(ordered)) - 1, 0)]


def spread(values):
    return {"p50": rank(values, 50), "p95": rank(values, 95)}


def jobs_of(repo, path, what):
    return gh(what, "api", f"repos/{repo}/actions/runs/{path}/jobs?per_page=100")["jobs"]


def is_setup(name, named):
    return name in SETUP_NAMES or name in named or name.startswith(SETUP_STARTS)


def time_jobs(runs, jobs_by_run, named):
    table = {}
    for run in runs:
        for job in jobs_by_run[run["databaseId"]]:
            if job.get("conclusion") in LEFT_OUT or not job.get("started_at") or not job.get("completed_at"):
                continue
            key = (run["workflowName"], job["name"])
            row = table.setdefault(key, {"wait": [], "setup": [], "work": [], "total": [], "steps": {}})
            total = seconds(job["started_at"], job["completed_at"])
            setup = 0
            for step in sorted(job.get("steps") or [], key=lambda s: s["number"]):
                if step.get("conclusion") == "skipped" or not step.get("started_at") or not step.get("completed_at"):
                    continue
                took = seconds(step["started_at"], step["completed_at"])
                row["steps"].setdefault(step["name"], []).append(took)
                if is_setup(step["name"], named):
                    setup += took
            row["wait"].append(seconds(job["created_at"], job["started_at"]))
            row["setup"].append(setup)
            row["work"].append(total - setup)
            row["total"].append(total)
    return [
        {
            "workflow": workflow,
            "job": job,
            "runs": len(row["total"]),
            "wait": spread(row["wait"]),
            "setup": spread(row["setup"]),
            "work": spread(row["work"]),
            "total": spread(row["total"]),
            "slowest": max(row["total"]),
            "steps": [{"name": name, **spread(times)} for name, times in row["steps"].items()],
        }
        for (workflow, job), row in table.items()
    ]




def main():
    parser = argparse.ArgumentParser(description="Time a repo's GitHub Actions runs.")
    parser.add_argument("repo")
    parser.add_argument("--runs", type=int, default=150)
    parser.add_argument("--setup", action="append", default=[], metavar="STEP")
    args = parser.parse_args()

    runs = gh("list runs", "run", "list", "-R", args.repo, "-L", str(args.runs), "--status", "completed", "--json", RUN_FIELDS)
    jobs_by_run = {run["databaseId"]: jobs_of(args.repo, run["databaseId"], f"list the jobs of run {run['databaseId']}") for run in runs}
    dates = sorted(run["createdAt"][:10] for run in runs)
    print(json.dumps({
        "repo": args.repo,
        "asked": args.runs,
        "runs": len(runs),
        "from": dates[0] if dates else None,
        "to": dates[-1] if dates else None,
        "jobs": time_jobs(runs, jobs_by_run, set(args.setup))
    }, indent=2))


if __name__ == "__main__":
    main()
