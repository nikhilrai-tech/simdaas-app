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


# Power Automate's "Post card in a chat or channel" action rejects a
# request over roughly 28 KB with RequestEntityTooLarge (confirmed live on
# the 1.1.5 release: its CHANGELOG section alone -- ~43 bullets across 39
# PRs -- produced a card past that limit; every earlier release's much
# shorter section had stayed under it by luck, not by design). Budget is
# deliberately conservative (the actions block, wrapper JSON, and HTTP
# headers all eat into the same request).
MAX_PAYLOAD_BYTES = 24000


def _title_block(tag: str) -> dict:
    return {
        "type": "TextBlock",
        "text": f"Krishi Spray {tag} released",
        "weight": "Bolder",
        "size": "Medium",
        "wrap": True,
    }


def _actions(release_url: str) -> list:
    return [
        {
            "type": "Action.OpenUrl",
            "title": "View release & download APK",
            "url": release_url,
        }
    ]


def _wrap(card: dict) -> dict:
    return {
        "type": "message",
        "attachments": [
            {"contentType": "application/vnd.microsoft.card.adaptive", "content": card}
        ],
    }


def build_payload(tag: str, notes: str, release_url: str) -> dict:
    elements = changelog_to_card_body(notes)
    title = _title_block(tag)
    actions = _actions(release_url)

    def card_with(n):
        body = [title, *elements[:n]]
        if n < len(elements):
            body.append({
                "type": "TextBlock",
                "text": "…see the full release notes for everything else in this release.",
                "wrap": True,
                "isSubtle": True,
                "spacing": "Medium",
            })
        return {
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "type": "AdaptiveCard",
            "version": "1.4",
            "body": body,
            "actions": actions,
        }

    # Start with everything; if that doesn't fit, drop trailing bullets
    # until it does. The release notes stay complete on GitHub either way
    # (this card is a notification, not the source of truth), and the
    # "View release" button is always there to read the rest.
    n = len(elements)
    while n >= 0:
        payload = _wrap(card_with(n))
        if len(json.dumps(payload).encode("utf-8")) <= MAX_PAYLOAD_BYTES or n == 0:
            return payload
        n -= 1


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
