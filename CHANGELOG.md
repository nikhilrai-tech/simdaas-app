# Changelog

All notable changes to this app are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions match
`pubspec.yaml`'s `version:` field and the git tag created for that release
(e.g. `v0.2.16`).

Every APK build should ship with the CHANGELOG entry for that version
already written — see "Release process" at the bottom.

## [Unreleased]

## [1.1.2] - 2026-08-26

### Added
- Satellite/Normal map view toggle on the Map Plot create/edit screen,
  the live Monitoring screen, and every map on Report Details (inline
  header, fullscreen view, and the no-GPS-data fallback). Defaults to
  satellite, matching current behavior until toggled.
- Report Details now has an editable "Additional Details" card for Driver
  Name and Fertilizers Used — free-text fields you fill in per report,
  defaulting to "N/A" until set. *(backend)*
- New "Left/Right" spray heatmap on Monitoring and Report Details —
  colors the track by which solenoid(s) sprayed (orange = left only,
  purple = right only, teal = both, white = neither), since the existing
  Spray heatmap's combined flow rate couldn't show which side sprayed.
  On Monitoring it's a "Flow / L-R" sub-toggle next to the legend once
  Spraying heat map is selected, rather than a separate menu entry.
  *(backend)*

### Changed
- Session auto-timeout (grace period after a device stops sending data
  before its session is closed and a report generated) increased from 10
  minutes to 60 minutes, so a temporary network drop in the field no longer
  prematurely ends an active spray session while the sprayer is still
  physically running. The "waiting" countdown on the Monitoring screen and
  the Active Devices list now reflect the same longer window. *(backend)*

### Fixed
- Monitoring screen's Flow LPM/Flow L/Speed/PTO summary could keep showing
  stale pre-reboot numbers after the sprayer device power-cycled mid-session
  (same "uptime resets on reboot" signal as the Average Speed fix below,
  now also used client-side) — a reboot now clears the cached values so a
  later gap falls back to post-reboot data instead of pre-reboot data.
- Logging out and signing in as a different user (without fully closing the
  app) no longer shows the previous user's Reports, Active Sessions, Jobs,
  Admin Users, or Firmware Alerts — these were cached in memory and never
  cleared on sign out, so they kept displaying stale data until the app was
  fully restarted. Signing out now clears all of it immediately.
- Report Details screen's Start/End session times now display in the
  phone's local time instead of raw UTC clock digits (was showing up to
  5.5 hours off from the actual time).
- Report's Average Speed could show higher than Max Speed when the sprayer
  device was rebooted mid-session (e.g. farmer power-cycles it and resumes
  spraying ~20 minutes later) — device uptime now correctly accumulates
  across reboots so Average Speed reflects the true session duration
  instead of only the time since the most recent reboot. *(backend)*
- Device config pushed to the sprayer (row spacing, wheel diameter, etc.)
  now reads wheel diameter from the sprayer instead of the tractor, both on
  config save and when toggling Demo Mode. *(backend)*
- A device whose sensor reported a bare `inf` value (e.g. an unconnected
  water-level sensor) had every single heartbeat silently dropped — the
  nan/Infinity sanitizer only recognized the word "Infinity", not `inf`, so
  the packet failed to parse and never reached the app, leaving the device
  stuck showing "Waiting" indefinitely even while actively transmitting.
  *(backend)*
- Report's Distance Travelled and Area Covered could be wildly inflated
  when the device's GPS briefly lost its fix (device reports lat/lon as
  0.0, 0.0 while unlocked) — a single dropped fix added a false
  multi-thousand-km jump to the session's running distance. Distance is no
  longer accumulated from an invalid (0, 0) fix, and a session that never
  gets a real GPS fix now shows a "GPS data unavailable for this session"
  note on the Report Details screen instead of a misleading 0 km / 0%
  coverage.
- Monitoring screen's live GPS track could disappear entirely or show a
  straight-line "jump" after minimizing the app — the track was held only
  in phone memory, so backgrounding long enough for Android to kill the
  app (or just drop the WebSocket for a while) lost it or left a gap. The
  screen now re-fetches the active session's track from the backend (which
  always has it, MQTT-side, independent of the app) on open and every time
  the app resumes from background.
- Report Details' "Chemical Saved" percentage was mixing Manual-mode
  distance into a metric meant to measure Auto-mode spray efficiency
  (solenoid toggled off manually was counted the same as Auto skipping a
  gap). Now computed from Auto-mode distance only; a session sprayed
  entirely in Manual mode shows a note explaining why instead of a
  misleading 0%. *(backend)*
- Spray heatmap (Monitoring and Report Details) showed 0 L/min flow as
  nearly the same light blue as a very low nonzero flow, making "no spray"
  hard to distinguish on the track. 0 L/min now renders white, and the
  1-70 L/min gradient spans light-to-dark blue so variation within that
  range is easy to read at a glance. Legend updated to match.
- Monitoring screen's network signal bars stayed plain white regardless of
  strength, hard to read at a glance on a small screen — now colored
  green/orange/red matching the adjacent GPS indicator's thresholds.
- GPS heatmap row-coverage bands could flip from Auto (blue) back to PTO
  Off (orange) or Manual (grey) from a single stray later sample at the
  same spot, wrongly implying spraying never happened there. A sub-band
  now only ever moves up in priority (PTO Off < Manual < Auto), never
  back down, for the rest of the session — same fix on Monitoring and
  Report Details since both share the same coverage-band code.

## [1.1.1] - 2026-08-06

### Fixed
- GPS coverage heatmap on the live Monitoring screen no longer gets stuck
  showing orange (PTO off) at a sub-band once the sprayer returns to that
  spot with PTO back on — the band now always reflects the most recently
  recorded PTO state instead of only the first pass ever recorded there.
- Device status (Active Devices list and Monitoring screen) no longer gets
  stuck showing a "Cooldown" badge with a dead timer if a status WebSocket
  update is missed — the app now resyncs every device's status against the
  backend on app start, login, and network reconnect, so a missed event
  self-corrects instead of leaving the badge stuck indefinitely.

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
