# Changelog

All notable changes to this app are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions match
`pubspec.yaml`'s `version:` field and the git tag created for that release
(e.g. `v0.2.16`).

Every APK build should ship with the CHANGELOG entry for that version
already written — see "Release process" at the bottom.

## [Unreleased]

## [1.1.0] - 2026-07-24

### Changed
- Report Details screen's "Chemical Saved" card now shows a real,
  backend-computed percentage instead of a hardcoded `40%`. Calculated as
  the share of potential spray distance (both solenoids, while PTO was on)
  where a solenoid was off — i.e. spraying was skipped.

## [1.0.0] - 2026-07-11

### Added
- **OTA Firmware Update** — new Firmware Update Workspace screen (RFC-004):
  version handshake (DB / S3-available / live-hardware version), WiFi
  credential prompt when the device has none stored, live progress bar,
  90-second post-flash verification countdown, and terminal success /
  rollback / critical-failure states — all driven live over the existing
  device WebSocket connection.
  - Device Detail screen: new "Firmware Version" row with a "Check Update"
    button that appears when a newer version is available.
- **Admin Dashboard** — was previously unreachable from the real login flow;
  now surfaced via a shortcut in the main dashboard's app bar (Super Admin
  accounts only).
  - New "Alerts" tab listing critical OTA failures/rollbacks across all
    devices.
  - New "All Users" screen — directory of every registered user (Super
    Admin only).
- **CHANGELOG.md** introduced to track release notes going forward, plus an
  automated release pipeline (see Release process below) that builds the
  APK, publishes a GitHub Release, and posts to the team's Teams channel.

### Fixed
- Firmware "Live Hardware Version" check no longer spins forever if the
  device never replies — times out after 20s with a retry option.
- Firmware update screen no longer gets permanently stuck (e.g. "Waiting to
  Connect...") if a WebSocket status update is missed — it now polls the
  backend as a fallback and resyncs to the real device state.
- Submitting WiFi credentials now moves straight into the update/progress
  step instead of waiting on a reply that never comes for that specific
  message.

## [0.2.16] - 2026-06-30
_Baseline at the start of OTA firmware update work — see git history for
changes prior to this changelog's introduction._

## [0.2.15] - 2026-06-29
_See git history._

---

## Release process (automated)

A push of a `v*.*.*` tag triggers `.github/workflows/release.yml`, which:
builds the release APK, extracts this file's section for that version,
creates a GitHub Release with the APK attached and that section as the
release notes, and (once `TEAMS_WEBHOOK_URL` is configured as a repo
secret — see the workflow file for setup instructions) posts the same
notes + a download link to the team's Teams channel.

To cut a release:

1. Decide the next version (semver-ish: `MAJOR.MINOR.PATCH+BUILD`).
2. Move the `[Unreleased]` section's contents under a new `## [X.Y.Z] - YYYY-MM-DD`
   heading; leave `[Unreleased]` empty above.
3. Bump `version:` in `pubspec.yaml` to match (the `X.Y.Z` part; bump the
   `+BUILD` too).
4. Commit, then tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`
   (and to `neworigin` if that remote is in use).
5. Watch the Actions tab — the release (APK + notes) appears automatically
   once the workflow finishes.
