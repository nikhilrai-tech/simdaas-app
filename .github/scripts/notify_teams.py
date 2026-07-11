#!/usr/bin/env python3
"""Post a release notification to a Teams channel via a "Post to a channel
when a webhook request is received" Workflow (Teams > channel > ... >
Workflows). That template's trigger expects a JSON body shaped
{"text": "<html>"} and posts `text` as the message.

This only posts a *link* to the APK (GitHub Release asset), not the raw
file — Teams webhooks/Workflows don't support arbitrary file uploads
without a more involved Graph API / SharePoint flow. See
docs in the release workflow for how to set the webhook URL up.

Usage: notify_teams.py <webhook_url> <tag> <release_url> <notes_file>
"""
import html
import json
import sys
import urllib.request


def markdown_to_teams_html(notes: str) -> str:
    lines = []
    for line in notes.splitlines():
        stripped = line.strip()
        if stripped.startswith("### "):
            lines.append(f"<b>{html.escape(stripped[4:])}</b>")
        elif stripped.startswith("- "):
            lines.append(f"&nbsp;&nbsp;&bull; {html.escape(stripped[2:])}")
        elif stripped:
            lines.append(html.escape(stripped))
    return "<br>".join(lines)


def main():
    if len(sys.argv) != 5:
        print(
            "Usage: notify_teams.py <webhook_url> <tag> <release_url> <notes_file>",
            file=sys.stderr,
        )
        sys.exit(1)

    webhook_url, tag, release_url, notes_path = sys.argv[1:5]
    notes = open(notes_path, encoding="utf-8").read().strip()
    body_html = markdown_to_teams_html(notes)

    text = (
        f"<b>Krishi Spray {html.escape(tag)} released</b><br>{body_html}"
        f'<br><br><a href="{release_url}">View release &amp; download APK</a>'
    )

    payload = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url, data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        print(f"Teams webhook responded: {resp.status}")


if __name__ == "__main__":
    main()
