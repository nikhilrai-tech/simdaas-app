# Changelog

All notable changes to this app are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions match
`pubspec.yaml`'s `version:` field and the git tag created for that release
(e.g. `v0.2.16`).

Every APK build should ship with the CHANGELOG entry for that version
already written — see "Release process" at the bottom.

## [Unreleased]

### Added
- **OTA Firmware Update** — new Firmware Update Workspace screen (RFC-004):
  version handshake (DB / S3-available / live-hardware version), WiFi
  credential prompt when the device has none stored, live progress bar,
  90-second post-flash verification countdown, and terminal success /
  rollback / critical-failure states — all driven live over the existing
  device WebSocket connection.
  - Device Detail screen: new "Firmware Version" row with a "Check Update"
    button that appears when a newer version is available.
  - Admin Dashboard: new "Alerts" tab listing critical OTA failures/rollbacks
    across all devices.
  - Dashboard app bar: new Admin Dashboard shortcut (shown only to Super
    Admin accounts) — previously unreachable from the real login flow.

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

## Release process

1. Decide the next version (semver-ish: `MAJOR.MINOR.PATCH+BUILD`).
2. Move the `[Unreleased]` section's contents under a new `## [X.Y.Z] - YYYY-MM-DD`
   heading; leave `[Unreleased]` empty (or delete it) above.
3. Bump `version:` in `pubspec.yaml` to match.
4. Build the release APK (`flutter build apk --release`).
5. Tag the commit: `git tag vX.Y.Z && git push origin vX.Y.Z`.
6. Attach this version's CHANGELOG section as the release notes wherever the
   APK is distributed (GitHub Release description, Firebase App Distribution
   release notes, etc.) — the APK and its changelog entry should always ship
   together.
