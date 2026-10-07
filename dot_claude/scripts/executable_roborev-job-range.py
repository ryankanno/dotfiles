#!/usr/bin/env python3
"""Print the roborev job reviewing a directory, and the range it reviews.

Usage: roborev-job-range.py <dir>
Prints "<job id>\t<git_ref>" and exits 0, or explains on stderr and exits 1.

The OCR plugin calls this so ocr_review reviews the change roborev is
reviewing. The review prompt lists the commits but never names the base, and a
range the agent works out for itself has handed OCR the wrong change.
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

ACTIVE = ("queued", "running")


def roborev(*args):
    out = subprocess.run(["roborev", *args], capture_output=True, text=True, timeout=20)
    if out.returncode != 0:
        sys.exit(out.stderr.strip() or f"roborev {' '.join(args)} failed")
    return out.stdout


def daemon_job(job_id):
    # `roborev show` answers only once a review exists, and `roborev list`
    # shows a panel's parent rather than the member a CI worktree belongs to.
    # The daemon's jobs endpoint, which `roborev wait` polls, returns any job.
    addr = roborev("config", "get", "server_addr").strip()
    if addr.startswith("unix:"):
        sys.exit(f"daemon listens on {addr}; only host:port addresses are supported")
    url = f"http://{addr.removeprefix('http://')}/api/jobs?id={job_id}"
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            jobs = json.load(response).get("jobs") or []
    except OSError as err:
        sys.exit(f"cannot reach the roborev daemon at {addr}: {err}")
    match = [j for j in jobs if j.get("id") == int(job_id)]
    if not match:
        sys.exit(f"the roborev daemon returned no job {job_id}")
    return match[0]


def same_dir(a, b):
    return bool(a and b) and os.path.realpath(a) == os.path.realpath(b)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: roborev-job-range.py <dir>")
    directory = sys.argv[1]

    # The CI poller reviews in ~/.roborev/ci-worktrees/<repo>/roborev-ci-<job>-<n>,
    # and stores no worktree_path on the job, so the directory is the only link.
    ci = re.match(r"roborev-ci-(\d+)-", os.path.basename(os.path.normpath(directory)))
    if ci:
        job = daemon_job(ci.group(1))
        print(f"{job['id']}\t{job['git_ref']}")
        return

    # A panel lists as its synthesis parent, which stays queued while its
    # members run; they share its git_ref.
    jobs = json.loads(roborev("list", "--all-branches", "--json", "--limit", "50", "--repo", directory))
    active = [j for j in jobs if j.get("status") in ACTIVE
              and same_dir(j.get("worktree_path") or j.get("repo_path"), directory)]
    refs = sorted({j["git_ref"] for j in active})
    if not refs:
        sys.exit(f"no queued or running roborev job reviews {directory}")
    if len(refs) > 1:
        sys.exit(f"roborev jobs in {directory} review different ranges: {', '.join(refs)}")
    newest = max(active, key=lambda j: j["id"])
    print(f"{newest['id']}\t{refs[0]}")


if __name__ == "__main__":
    main()
