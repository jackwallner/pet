#!/usr/bin/env python3
"""Read and update tester suggestions (the tester-feedback edge function).

  feedback.py list [--status new]                  suggestions with that status
  feedback.py show <id> [--screenshot out.jpg]     one suggestion, optionally saving its screenshot
  feedback.py status <id> <status> [--build N] [--reply TEXT]
      status: working | shipped | needs_jack | declined | failed

Credentials: ~/.tester_feedback (TESTER_FEEDBACK_URL, TESTER_FEEDBACK_ADMIN_KEY).
The tester sees `status`, `build` and `reply` under Settings > Suggestions in the app.
"""
from __future__ import annotations

import argparse
import base64
import json
import pathlib
import sys
import urllib.request

STATUSES = ["working", "shipped", "needs_jack", "declined", "failed", "new", "queued"]


def creds() -> tuple[str, str]:
    env = {}
    for line in (pathlib.Path.home() / ".tester_feedback").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env["TESTER_FEEDBACK_URL"], env["TESTER_FEEDBACK_ADMIN_KEY"]


def call(method: str, query: str = "", body: dict | None = None):
    url, key = creds()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + query, data=data, method=method,
                                 headers={"x-admin-key": key, "content-type": "application/json",
                                          "user-agent": "pet-feedback/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    ls = sub.add_parser("list")
    ls.add_argument("--status", default="new")
    sh = sub.add_parser("show")
    sh.add_argument("id", type=int)
    sh.add_argument("--screenshot")
    st = sub.add_parser("status")
    st.add_argument("id", type=int)
    st.add_argument("status", choices=STATUSES)
    st.add_argument("--build")
    st.add_argument("--reply")
    a = ap.parse_args()

    if a.cmd == "list":
        for row in call("GET", f"?status={a.status}"):
            print(f"#{row['id']} {row['created_at'][:16]} {row['app']} {row['name'] or '-'}: {row['text'][:120]}")
    elif a.cmd == "show":
        row = call("GET", f"?id={a.id}")
        shot = row.pop("screenshot", None)
        if a.screenshot and shot:
            pathlib.Path(a.screenshot).write_bytes(base64.b64decode(shot))
            row["screenshot_saved_to"] = a.screenshot
        row["has_screenshot"] = bool(shot)
        print(json.dumps(row, indent=1))
    else:
        body = {"id": a.id, "status": a.status}
        if a.build:
            body["build"] = a.build
        if a.reply:
            body["reply"] = a.reply
        row = call("PATCH", body=body)
        print(f"#{row['id']} -> {row['status']}" + (f" (build {row['build']})" if row.get("build") else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
