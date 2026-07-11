# Deployment & Release Guide

How to cut a new release of the Krishi Spray (simdaas) app, what happens
automatically once you do, and what to check if something goes wrong.

## The short version

```bash
# 1. Write what changed under [Unreleased] in CHANGELOG.md
# 2. Bump the version in pubspec.yaml (X.Y.Z part, and the +BUILD)
# 3. Commit, then tag and push to BOTH remotes:
git add CHANGELOG.md pubspec.yaml
git commit -m "Release vX.Y.Z"
git tag vX.Y.Z
git push origin main && git push origin vX.Y.Z
git push neworigin main && git push neworigin vX.Y.Z
```

That's it. Pushing the tag triggers everything else automatically (see
below). Watch the "Actions" tab on either repo — the release (APK +
notes) shows up there in a few minutes, and a card posts to the Teams
"release channel - Krishi apk" channel.

## Why two remotes

This repo pushes to two separate GitHub repos, and a release needs to go
to **both** or they'll drift apart:

| Remote | Repo | Notes |
|---|---|---|
| `origin` | `nikhilrai-tech/simdaas-app` | |
| `neworigin` | `simdaasai/krishi-spray-fronend` | the newer org repo |

Both have the identical `.github/workflows/release.yml` and both have the
`TEAMS_WEBHOOK_URL` secret configured — releasing on only one will leave
the other's `main`/tags behind and its GitHub Releases page stale.

Check `git branch --show-current` before starting a release — the day-to-day
working branch has been `main-frontend-livesync` (tracks `neworigin/main`),
not `main` locally. Merge/rebase it onto both remotes' `main` before tagging
if it isn't already, e.g.:

```bash
git fetch origin main && git fetch neworigin main
# make sure your branch has everything from both remotes' main, then:
git push origin HEAD:main
git push neworigin HEAD:main
```

## What happens automatically after a tag push

`.github/workflows/release.yml` triggers on any `v*.*.*` tag push (on
either remote independently — each repo's Actions run separately) and:

1. Builds the release APK (`flutter build apk --release`). **Note:** the
   app is currently signed with the **debug** keystore
   (`android/app/build.gradle`'s `signingConfig = signingConfigs.debug`) —
   fine for direct-install distribution to the client, but if this ever
   needs to go through the Play Store, a real release keystore has to be
   generated and wired in first.
2. Extracts the `## [X.Y.Z]` section from `CHANGELOG.md` matching the
   tag's version (`.github/scripts/extract_changelog.py`). If that section
   doesn't exist, the release notes just say so — **the workflow does not
   invent changelog content**, it only reads what's already written. Write
   the CHANGELOG.md entry *before* tagging, not after.
3. Creates a GitHub Release for that tag with the APK attached and the
   extracted section as the release notes (`softprops/action-gh-release`).
4. Posts the same notes + a link to the release to the Teams channel via
   `.github/scripts/notify_teams.py`, using the `TEAMS_WEBHOOK_URL` repo
   secret. If that secret isn't set, this step prints a message and skips
   — it does not fail the build.

Nothing happens on a normal `git push` to `main` without a tag — only tag
pushes matching `v*.*.*` trigger the workflow.

## Teams webhook (already set up — for reference / if it ever needs redoing)

The webhook posts to the **"release channel - Krishi apk"** Teams channel
via a Power Automate "Workflow", not a plain Incoming Webhook connector
(those are deprecated). To (re)create it:

1. Open the Teams channel → **"..." (more options) → Workflows**.
2. Search **"webhook"** in the template search (the top-level suggestion
   tiles shown by default won't include it — you have to search).
3. Pick **"Send webhook alerts to a channel"** (description mentions
   GitHub/Zapier explicitly — this is the right one).
4. Point it at the channel, name it, finish creating it. Teams gives you a
   URL at the end.
5. Set that URL as the `TEAMS_WEBHOOK_URL` secret on **both** repos:
   `gh secret set TEAMS_WEBHOOK_URL --repo <owner>/<repo>` (or via each
   repo's Settings → Secrets and variables → Actions).

**Important gotcha**: this trigger expects a Teams **Adaptive Card**
payload (`{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{...}}]}`),
**not** the simpler `{"text": "..."}` MessageCard shape older webhook
docs describe. Sending the wrong shape doesn't error out at the HTTP
level — the webhook still returns `202 Accepted` — it fails silently
*inside* the Power Automate flow (its "Attachments is null" branch tries
to post an empty card and gets a Teams `BadRequest`). `notify_teams.py`
already builds the correct Adaptive Card shape; if this ever needs
rebuilding from scratch, check the flow's run history in Power Automate
(via the workflow's "..." menu → Edit, or make.powerautomate.com → My
flows) rather than assuming a 202 means the message actually posted.

Also note: **re-pushing/force-moving an existing tag re-triggers the
workflow**, including another Teams post. If you ever need to move a tag,
expect a duplicate-looking card in the channel — harmless, but don't be
surprised by it.

## Troubleshooting

**Workflow shows "This run likely failed because of a workflow file
issue" with 0s duration and no logs.** This is GitHub rejecting the YAML
as invalid — it's not a build/runtime failure. Confirmed cause once
already: a step's `if: ${{ secrets.SOME_SECRET != '' }}` condition made
the whole file invalid (no useful error message pinpointing it — GitHub
just flags the file generically). Fix: don't gate steps on `secrets.X` in
`if:`. Instead, always run the step and have the script itself check
`if not value: skip` (see how `notify_teams.py` does it). If you hit this
again, bisect by temporarily replacing the workflow with a trivial one and
adding pieces back until it reproduces.

**Release created but no Teams message.** Check the job's "Notify Teams"
step log first (`gh run view <id> --log`) — it prints
`Teams webhook responded: 202` on success from GitHub's side. If that's
there but nothing shows in Teams, the problem is downstream in Power
Automate — check that flow's run history for the real error (see the
Adaptive Card gotcha above).

**CHANGELOG.md section not found / release notes say "_No CHANGELOG.md
entry found_".** The version parsed from the tag (`vX.Y.Z` → `X.Y.Z`)
didn't exactly match a `## [X.Y.Z]` heading in CHANGELOG.md. Check for
typos/mismatched versions between the tag and the heading.

**Need to rebuild release for the same tag** (e.g. fixing something after
a bad release): delete the GitHub Release and the tag on both remotes and
both local + remote (`gh release delete vX.Y.Z --repo <owner>/<repo>
--cleanup-tag`, `git tag -d vX.Y.Z`), fix things, re-tag, re-push.
