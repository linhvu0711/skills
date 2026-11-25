#!/usr/bin/env python3
"""Time a repo's GitHub Actions runs: how long each job waits for a machine,
how long its setup, its work, each step, and the whole job take, how long
a PR commit waits for its last result, and which runs needed a re-run.

    ci_times.py <owner/repo> [--runs N] [--setup <step name>]...

Reads the last N completed runs (default 150) with `gh`, then each run's
jobs. Prints one JSON object:

    {"repo", "asked", "runs", "from", "to",
     "pr_result": {"results", "p50", "p95"},
     "jobs": [{"workflow", "workflow_id", "job", "runs", "wait": {"p50", "p95"},
               "setup": {"p50", "p95"}, "work": {"p50", "p95"},
               "total": {"p50", "p95"}, "slowest",
               "steps": [{"name", "p50", "p95"}]}],
     "reruns": [{"run", "workflow", "attempts", "conclusion", "failed_first"}]}

A job is keyed by its workflow's id, so two workflow files that share a
name keep apart; `workflow_id` tells them apart. Times are whole seconds. A job's wait is its start minus its creation, the
time it sat in the queue for a machine. Setup is the sum of a run's setup
steps: `Set up job`, `Complete job`, a step whose name starts with `Post `,
`Run actions/checkout`, `Run actions/setup-`, or `Run actions/cache`, and
each step a `--setup` names. Work is the job's total minus its setup, taken
per run before any percentile, since percentiles do not add. A PR result is
one batch of pull_request runs on one commit: it runs from the creation of
its first run to the last update of its last run. A run on the same commit
that starts after the batch ends, or a second run of a workflow the batch
already holds, as when a draft is marked ready, starts a new result. A percentile
is nearest rank, so each one is a real run's time. Skipped and cancelled
jobs and skipped steps are left out. With no PR runs, `pr_result` is
{"results": 0}; with no runs, `runs` is 0 and `jobs` and `reruns` are [].
A re-run's `failed_first` names the jobs that failed on its first attempt.
A run's jobs come in pages of 100; every page is read.

A gh call that fails stops with `stop: gh could not <what>: <gh's last
line>` on stderr and exit 1.
"""

import argparse
import datetime as dt
import importlib.util
import json
import math
import os

# Loaded by path: `python3 -I` leaves the script's folder off sys.path.
_spec = importlib.util.spec_from_file_location("gh", os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", "shared", "gh.py"))
GH = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(GH)

RUN_FIELDS = "databaseId,attempt,createdAt,updatedAt,event,headSha,workflowName,workflowDatabaseId,conclusion"
LEFT_OUT = {"skipped", "cancelled"}
SETUP_NAMES = {"Set up job", "Complete job"}
SETUP_STARTS = ("Post ", "Run actions/checkout", "Run actions/setup-", "Run actions/cache")
PAGE = 100


def gh(what, *args):
    return json.loads(GH.stop(what, *args) or "null")


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
    jobs, page = [], 1
    while True:
        found = gh(what, "api", f"repos/{repo}/actions/runs/{path}/jobs?per_page={PAGE}&page={page}")["jobs"]
        jobs += found
        if len(found) < PAGE:
            return jobs
        page += 1


def is_setup(name, named):
    return name in SETUP_NAMES or name in named or name.startswith(SETUP_STARTS)


def time_jobs(runs, jobs_by_run, named):
    table = {}
    for run in runs:
        for job in jobs_by_run[run["databaseId"]]:
            if job.get("conclusion") in LEFT_OUT or not job.get("started_at") or not job.get("completed_at"):
                continue
            key = (run["workflowDatabaseId"], run["workflowName"], job["name"])
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
            "workflow_id": workflow_id,
            "job": job,
            "runs": len(row["total"]),
            "wait": spread(row["wait"]),
            "setup": spread(row["setup"]),
            "work": spread(row["work"]),
            "total": spread(row["total"]),
            "slowest": max(row["total"]),
            "steps": [{"name": name, **spread(times)} for name, times in row["steps"].items()],
        }
        for (workflow_id, workflow, job), row in table.items()
    ]




def time_pr_results(runs):
    by_commit = {}
    for run in runs:
        if run["event"] == "pull_request":
            by_commit.setdefault(run["headSha"], []).append(run)
    spans = []
    for same in by_commit.values():
        start = end = None
        seen = set()
        for run in sorted(same, key=lambda r: when(r["createdAt"])):
            if end and (when(run["createdAt"]) > when(end) or run["workflowDatabaseId"] in seen):
                spans.append(seconds(start, end))
                start, seen = None, set()
            seen.add(run["workflowDatabaseId"])
            if start is None:
                start, end = run["createdAt"], run["updatedAt"]
            else:
                end = max(end, run["updatedAt"], key=when)
        spans.append(seconds(start, end))
    if not spans:
        return {"results": 0}
    return {"results": len(spans), **spread(spans)}


def list_reruns(repo, runs):
    reruns = []
    for run in runs:
        if run["attempt"] > 1:
            first = jobs_of(repo, f"{run['databaseId']}/attempts/1", f"list the first attempt of run {run['databaseId']}")
            reruns.append({
                "run": run["databaseId"],
                "workflow": run["workflowName"],
                "attempts": run["attempt"],
                "conclusion": run["conclusion"],
                "failed_first": [job["name"] for job in first if job.get("conclusion") == "failure"],
            })
    return reruns


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
        "pr_result": time_pr_results(runs),
        "jobs": time_jobs(runs, jobs_by_run, set(args.setup)),
        "reruns": list_reruns(args.repo, runs),
    }, indent=2))


if __name__ == "__main__":
    main()
