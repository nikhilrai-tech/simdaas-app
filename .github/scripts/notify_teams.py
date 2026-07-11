#!/usr/bin/env python3
"""Post a release notification to a Teams channel via the "Send webhook
alerts to a channel" Workflow (Teams > channel > ... > Workflows).

That template's trigger expects a Teams "Adaptive Card via webhook" body
shaped like:
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "content": { "$schema": ..., "type": "AdaptiveCard", "version": "1.4", "body": [...] }
    }
  ]
}
A plain {"text": "..."} body (the older, simpler Incoming Webhook /
MessageCard shape) is NOT accepted by this trigger — confirmed via a
failed run: the flow's "Attachments is null" check went down the branch
that tries to post an (empty) card and got a Teams BadRequest.

This only posts a *link* to the APK (GitHub Release asset), not the raw
file — Teams webhooks/Workflows don't support arbitrary file uploads
without a more involved Graph API / SharePoint flow.

Usage: notify_teams.py <webhook_url> <tag> <release_url> <notes_file>
"""
import json
import sys
import urllib.request


def changelog_to_card_body(notes: str) -> list:
    """Turns a CHANGELOG.md section into Adaptive Card TextBlock elements."""
    elements = []
    for line in notes.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("### "):
            elements.append({
                "type": "TextBlock",
                "text": stripped[4:],
                "weight": "Bolder",
                "wrap": True,
                "spacing": "Medium",
            })
        elif stripped.startswith("- "):
            elements.append({
                "type": "TextBlock",
                "text": f"• {stripped[2:]}",
                "wrap": True,
            })
        else:
            elements.append({"type": "TextBlock", "text": stripped, "wrap": True})
    return elements


def build_payload(tag: str, notes: str, release_url: str) -> dict:
    card = {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.4",
        "body": [
            {
                "type": "TextBlock",
                "text": f"Krishi Spray {tag} released",
                "weight": "Bolder",
                "size": "Medium",
                "wrap": True,
            },
            *changelog_to_card_body(notes),
        ],
        "actions": [
            {
                "type": "Action.OpenUrl",
                "title": "View release & download APK",
                "url": release_url,
            }
        ],
    }
    return {
        "type": "message",
        "attachments": [
            {"contentType": "application/vnd.microsoft.card.adaptive", "content": card}
        ],
    }


def main():
    if len(sys.argv) != 5:
        print(
            "Usage: notify_teams.py <webhook_url> <tag> <release_url> <notes_file>",
            file=sys.stderr,
        )
        sys.exit(1)

    webhook_url, tag, release_url, notes_path = sys.argv[1:5]
    if not webhook_url:
        # TEAMS_WEBHOOK_URL secret isn't set yet — skip quietly rather than
        # gating this step on `if: secrets.X != ''` in the workflow, which
        # GitHub Actions rejected as an invalid workflow file in testing.
        print("TEAMS_WEBHOOK_URL not set — skipping Teams notification.")
        return

    notes = open(notes_path, encoding="utf-8").read().strip()
    payload = json.dumps(build_payload(tag, notes, release_url)).encode("utf-8")

    req = urllib.request.Request(
        webhook_url, data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        print(f"Teams webhook responded: {resp.status}")


if __name__ == "__main__":
    main()
