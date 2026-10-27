# Changelog

All notable changes to this app are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions match
`pubspec.yaml`'s `version:` field and the git tag created for that release
(e.g. `v0.2.16`).

Every APK build should ship with the CHANGELOG entry for that version
already written — see "Release process" at the bottom.

## [Unreleased]

## [1.1.5] - 2026-10-23

### Added
- **Manual (device-managed) session mode** — a new Session Mode toggle
  (Automatic / Manual) on each device's Equipment Details screen.
  Automatic keeps today's behavior (the backend infers session start/end
  from telemetry). In Manual, the sprayer firmware owns the session: it
  starts and ends only when you start/stop it — the button on the
  sprayer, or Start/End Session on the Monitoring screen. Data recorded
  while the device is offline mid-session is kept on the device and
  merged into the same session once it reconnects, instead of being
  lost to a network gap. Switching to Manual is blocked with a clear
  reason if the server-side feature isn't enabled yet, the device's
  firmware doesn't support it yet, or a session is currently active.
  *(backend)*
- Monitoring screen: a MANUAL title chip, an idle banner ("Manual mode —
  no session running") with its own Start Session button when a Manual
  device is online with nothing running, and End-session dialog copy
  that explains the Manual flow (stop is sent to the sprayer; the
  session ends once it confirms). Live values (flow rate, speed, PTO,
  tank level, GPS) keep showing on this screen even while idle — the
  sprayer keeps sending heartbeats whether or not a session is running,
  and these reflect that directly, independent of the session-only
  totals (distance, area covered, spray used).
- Active Devices dashboard: a new "Session Open" filter/status, separate
  from "Waiting" — a Manual device that's gone unreachable mid-session
  (still recording locally, no timeout, no countdown) is a different
  situation from Automatic's 60-minute watchdog and is no longer grouped
  with it. *(backend)*
- Reports: a small Automatic/Manual badge, and an "Updated" badge/banner
  when a report was recomputed after offline-recovered data was merged
  in from a reconnecting device, plus a "may be incomplete — pending
  network data" badge for a report whose session was force-closed after
  a long connectivity gap and hasn't been corrected yet. *(backend)*
- Manual sessions now show a compact MAC-SessionID identifier (e.g.
  `88A35AC5E658-29`, the device's own session counter) next to the
  Automatic/Manual badge — live on the Monitoring screen title while a
  session is running, and on the report afterwards. *(backend)*
- Optional Session PIN for switching a device between Automatic and
  Manual mode — an admin-set 4-6 digit PIN (Django admin only, not
  self-service) that a farmer's account can require before the session
  mode changes either direction. Off by default for every account;
  only prompts once an admin has actually set one. Start/End Session
  itself is unaffected. *(backend)*
- Report map now highlights the crop rows recovered via backfill after a
  connectivity gap as a filled purple band (matching the width and style
  of the other GPS heatmap bands, e.g. the orange "PTO Off" fill) instead
  of a thin center-line trace, with a matching legend entry. GPS heatmap
  only, with its own on/off toggle there — previously showed as a thin
  line on every heatmap mode (GPS/Speed/Spray/L-R) unconditionally.
  Report-only, not shown live on the Monitoring screen. *(backend)*
- Manual session reports now show the sprayer's own start/end time
  (from the firmware, converted to local time) instead of the time the
  server happened to receive the data — so a session recovered late via
  backfill shows when it actually ran, not when it reconnected.
  Automatic reports are unaffected and keep showing server time as
  before. A "Prefilled" badge now appears on a report that includes any
  backfill-recovered data, next to the Automatic/Manual badge, on both
  the reports list and report details screens. *(backend)*
- A Prefilled report can now be cross-checked against the sprayer's own
  on-SD-card log once it's back online, instead of trusting the recovered
  (backfill) numbers indefinitely — a grey "Verifying" badge shows while
  that check is in progress; matching totals flip it to a new green
  "Verified" badge; a real mismatch or a log that can't be retrieved
  flips it to a red "Needs Review" badge with a note explaining why
  (which numbers didn't match, or why verification couldn't complete), on
  both the reports list and report details screens. Off by default per
  environment until the SD-card log pipeline is turned on there.
  *(backend)*
- A Verified report now also gets a prominent green banner at the top of
  the report details screen ("Verified — Matches the sprayer's own
  on-device log"), not just the small badge.
- A new grey "Live" badge for a Manual report that was built entirely
  from normal, real-time telemetry and never needed backfill recovery at
  all. Previously this case showed no badge whatsoever, so there was no
  way to tell where a report's data actually came from — Live (normal),
  Backfill (recovered after a connectivity gap), or Log-Verified
  (recovered data since confirmed against the device's own SD-card log).
  Automatic reports are unaffected — every Automatic report is always
  "live" since verification never runs on it, so the badge would be pure
  noise there. *(backend)*
- A "STAGING" ribbon now shows on every screen for any build pointed at
  the staging backend, so an APK handed to the testing team is never
  mistaken for a production build. Derived automatically from
  `apiBaseUrl` — no separate flag to remember to flip, and no risk of
  it staying wrong after `apiBaseUrl` is switched.
- Non-blocking status dialog for Start/End Session — a "Sending…" step
  appears the instant you tap, a persistent "waiting for device" spinner
  while the backend retries a lost command (with a live "Retrying…
  (attempt N)" readout), and a blocking "no response from device"
  dialog on a genuine ~20s timeout. Confirmation now also falls back to
  the device's own heartbeat if its explicit acknowledgement gets lost,
  so a session that visibly started no longer still shows "No
  response." *(backend)*
- Reports list: pagination (10 per page, Prev/Next) backed by a real
  server-side page fetch, so opening the list on an account with a long
  history doesn't pull every report before showing anything. A Today
  (default) / This week / This month / Custom date-range filter sits
  alongside the existing Field/Unit filters, filtered server-side the
  same way. *(backend)*
- Settings: new "Heatmap colors" section — the Speed (yellow/green/red)
  and Spray (blue/red/black) heatmap color-band boundaries are now
  editable per account (PIN-gated, same as switching Session Mode),
  with the map and its legend updating live and staying in sync with
  whatever was last saved. *(backend)*
- Settings: new "GPS calibration" section — a per-user north/east
  offset (metres) correcting a GPS receiver's own fixed positional
  bias, PIN-gated, applied server-side before a position is ever
  stored. *(backend)*
- Settings: "Fix report plot" — lets a device owner assign the correct
  plot to a report that was generated against the wrong one (or none at
  all), e.g. because the device wasn't mapped to the real plot yet at
  spray time; the report is recomputed and marked "Plot Updated."
  Includes the same date-range filter and pagination as the main
  Reports list. *(backend)*
- Share a report as a branded PDF (WhatsApp/Email/etc.) from the Report
  Details screen's share icon — a 4-page PDF (Summary, Spray, GPS,
  Speed, plus a 5th Left/Right page) with the real captured heatmap for
  each mode, not just a bare plot outline. An Email button next to
  Share sends the identical PDF straight to the account's registered
  email via the backend. *(backend)*
- Offline map tiles — any tile the app has shown is cached to disk and
  reused with no network round-trip next time; a new "Download for
  offline" button on plot creation/edit pre-fetches a plot's whole area
  (satellite or normal, zoom 15–20) so it, and the Monitoring screen for
  that plot, load instantly in the field with no signal.
- OTA firmware update: a WiFi/Cellular choice on the Update button —
  WiFi is unchanged (default, live progress %); Cellular is a new,
  slower (~2 min) path with no percentage. *(backend)*
- Monitoring screen: sprayer battery voltage shown in the GPS/Signal
  status chip (green/orange/red by level), hidden entirely on older
  firmware that doesn't send it yet. *(backend)*
- Monitoring screen: a dismissible banner when the sprayer's SD card
  goes missing mid-session — dismissing only silences that episode;
  pulling the card again after reinserting it re-alerts. *(backend)*
- Equipment Troubleshooting screen updated to the current firmware LED
  status reference (normal operation, power on, session button, OTA,
  log upload/retrieval, commands), with each pattern shown animated
  instead of as a static description.
- Row Editing: a rotation control (±10°, 0.1° steps) on Row 1 so a
  manually shifted field's angle can be corrected without re-drawing
  it — targets small heatmap gaps caused by an angle mismatch against
  the true rows. Rotating Row 1 rotates every row together, each still
  pivoting around its own midpoint and re-clipped to the plot boundary
  — letting rows rotate independently let their angles drift apart,
  which broke the row-corridor area calculation (each corridor's
  tolerance is derived from its own current gap to its neighbors) once
  a field had a manually rotated row.

### Changed
- Manual Start/End session controls consolidated into the Monitoring
  screen's AppBar — a plain "● Ongoing" status chip when a Manual
  session is running, with Start/End moved into the overlay menu
  instead of split between a title button and a buried menu item.
  Automatic mode's own "End active device" control is unchanged.
- Dragging a row line (Row Lines screen) now slides the whole row
  sideways across its own corridor (parallel shift, clipped to the
  plot boundary, limited by its real neighbors) instead of pivoting
  around the far end; rotation by dragging is gone, replaced by the
  new dedicated rotation control above.
- Settings screen redesigned to match the app's own design system
  (themed Save buttons, section headers, single-row band/offset
  layout) — the Heatmap colors and GPS calibration sections had been
  using generic, unthemed Material defaults.
- Monitoring screen's live-position badge is a dark circular icon badge
  instead of a plain blue dot, which happened to be the exact blue the
  GPS heatmap's own "Auto" legend color uses and could read as part of
  the heatmap.
- Monitoring screen's live sprayer marker is now a fixed icon/color
  instead of recoloring itself from PTO/heatmap state on every update;
  the underlying heatmap rendering is unchanged.
- Report verification wording in the details screen and fallback
  messages now reads in plain language ("your sprayer's own record")
  instead of developer-facing phrasing ("on-device log"). *(backend)*
- The "Report updated after network data was recovered" popup lost its
  View button (which only ever opened an empty stub screen) in favor
  of a plain close icon.

### Fixed
- The live WebSocket connection (telemetry, session status, cooldown,
  report-ready) always pointed at production, regardless of which
  backend the REST API (`apiBaseUrl`) was actually configured for — so
  pointing the app at staging silently left all *live* updates talking
  to production instead. Now derived from the same host as `apiBaseUrl`.
- Monitoring screen could briefly flicker or lose live data (the Manual
  idle banner, tank/solenoid/sensor overlays) on any background provider
  refresh — a loading state was being treated as "no data" instead of
  keeping the last known value until fresh data arrived.
- A device sitting idle in Manual mode (online, no session running right
  now) could suddenly start showing a *different* device's name and
  session on its own Monitoring screen, whenever exactly one other
  device in the account happened to have an active session at that
  moment.
- A Manual-mode device going offline showed the same 60-minute "Waiting"
  countdown Automatic mode uses — Manual mode has no such concept, since
  the sprayer (not a timeout) decides when it reconnects.
- The top-left L/R nozzle indicator card overlapped the Manual "Start
  Session" banner when both were visible at once.
- "End session" could be tapped on a Manual device with no live
  heartbeat (gone unreachable mid-session) — the Stop command it sends
  has no way to reach the device and no way to ever confirm, so the tap
  went nowhere. Now greyed out and disabled for a Manual device that
  isn't currently sending live telemetry, with a tooltip explaining why.
- Removed the "Report generated! Tap to view." snackbar that popped up
  on the Monitoring screen whenever a session ended.
- The MAC-SessionID label on the Monitoring screen title could
  incorrectly stay hidden even while a Manual session was genuinely
  running — it was waiting on a separate, slower REST-loaded session id
  that commonly hadn't caught up yet with the live telemetry already
  showing the real one.
- The top-left L/R nozzle indicator card and the legend below it could
  still overlap the Manual "Start Session" banner on narrower phone
  screens, where the banner's text wraps to an extra line — the previous
  fix used a fixed guessed offset that didn't account for that. Now
  measures the banner's actual height and shifts down by exactly that
  much.
- A report's Automatic/Manual badge, data-composition badge
  (Normal/Backfill/Log Updated) and verification-pipeline badge
  (Pending/Verifying/Verified/Needs Review) could collapse into one
  field trying to carry two meanings at once — now three always-
  independent badges, in a fixed order (Manual → composition →
  verification → MAC-session ID) on both the reports list and report
  details screens. *(backend)*
- Deleting a row line merged its two neighbors into one oversized
  coverage corridor, crediting the now-empty gap as covered. A deleted
  row now leaves two independent, normal-width edge bands instead, with
  no credit for the genuinely empty stretch between them — the same fix
  also applies to an old plot with a large unmarked gap left over from
  before the delete button existed. *(backend)*
- Row-fill heatmap could draw skewed blocks and triangles spilling
  outside the plot on a tapering (non-rectangular) field — row
  corridors clipped to the polygon end at different lengths, and the
  old gap-width measurement mistook that stagger for the corridor's
  real width. Corridors are now measured and bounded against the true
  clipped row lines; a corridor also now runs the full width of the
  plot (cut only by the boundary), and the stretch between the
  boundary and the first/last row counts as its own corridor too.
  *(backend)*
- Updating a Plot, Tractor, or Control Unit blocked the whole screen
  behind a spinner with no real confirmation if the save was slow —
  looked the same whether it was still working or had already failed.
  Saves now run in the background with a dismissible "Saving…" banner
  and a confirmation (success or failure) that reaches you even after
  navigating away; dismissing the banner only stops watching the save,
  it doesn't cancel it.
- Live Monitoring heatmap could show a farmer's own idle driving
  (Manual mode, no session running yet) or a mid-session connectivity
  gap's later-recovered points as if they were live, actively-sprayed
  coverage. Both are now excluded from what's drawn live; the finished
  report (which has the real recovered data either way) is unaffected.
- A GPS fix glitching to an implausible position (a "jump") could paint
  a long stretch of the wrong row as covered, or leave a blank gap
  where real spraying happened — fixed across several real sessions: a
  jump is now flagged and shown as a pink line (plus a small marker at
  both ends so even a small jump stays visible at any zoom) instead of
  silently bridged into coverage; a brief glitch is credited to the row
  trusted just before it rather than scattering across neighbors or
  painting the wrong one; and a forced credit is now bounded both by
  how far off a row's own line it can be and how far along the row it
  can bridge-fill, so a jump landing near — but not on — a different
  row can no longer paint either the wrong corridor or an implausibly
  long stretch of the right one.
- An ordinary row-to-row turn (driving out to the headland and back
  between rows) could leave a blank gap on the heatmap, the same as a
  genuine GPS glitch, even though nothing was wrong with the GPS.
  Points mid-turn are now credited to the row just left (shown as a
  small hollow amber marker, anchored to that row's own line rather
  than the turn's raw, off-corridor position) and retroactively
  reattributed to the new row if the turn turns out to be a real move
  there.
- GPS heatmap sub-bands could flip from a confirmed Auto pass back to
  Manual or PTO-off from a single stray later reading in the other
  mode. The two PTO-on modes now share priority (a later genuine pass
  in either mode wins), while PTO-off still never overrides either.
- Reports list / Report Details screens could keep showing a stale
  snapshot (Pending/Verifying long after a report actually finished) —
  their 30-second auto-refresh timers were declared in a way that, in
  Dart, meant they never actually started running. Both screens now
  refresh live as intended; Report Details also gained pull-to-refresh.
- A device sitting idle in Manual mode (online, no session running
  right now) could suddenly start showing a *different* device's name
  and session on its own Monitoring screen, whenever exactly one other
  device in the account happened to have an active session at that
  moment.
- Reports list "Past 2 months" date filter could spin forever without
  finishing — a timestamp computed fresh on every rebuild never matched
  the previous one exactly, so the list kept restarting into "loading"
  instead of settling. Filters are now stable within a day, matching
  how "This month" already worked.
- A burst of redundant "back online" events from the connectivity
  library (observed firing every 1–3 seconds with no real state
  change) triggered a full reconnect pass each time — resubscribing
  every device's telemetry, re-checking every control unit's cooldown
  state, and invalidating several providers, all at once, repeatedly —
  which is what made unrelated screens like Reports feel slow or
  outright fail to load. Only a genuine online/offline transition
  triggers this now.
- Reports list fetched an account's entire report history client-side
  before filtering/paginating it — an account with hundreds of reports
  could take ~18 sequential requests before the screen showed anything.
  The backend now does the filtering/sorting/paging itself, so
  changing a filter or page is a single request. *(backend)*
- The Plot Details screen could keep showing stale row lines/map/
  details after saving a change and returning to it — it read a fixed
  snapshot from when it was first opened rather than watching for
  updates; it now picks up every save immediately.
- Manual Start/End Session could show a brief, easy-to-miss
  confirmation that didn't actually mean the device had processed the
  request, with no way to tell a slow request from a lost one — see
  the Added entry above for the full fix.
- A report generated before the backend started freezing a plot's
  geometry at generation time could show garbled/triangle-shaped row
  coverage if that plot's rows were edited afterward, since it fell
  back to looking up the plot's current (now-mismatched) shape.
  Affected reports now fall back to a plain polygon + GPS path with a
  short note explaining why, instead of a garbled heatmap. *(backend)*
- Sharing a report crashed on real devices in several different ways
  while this was being built out (a missing temp-directory plugin, then
  an unsupported temp-directory call on Android, then a web build
  mistakenly exercising native-only code) — now uses the app's own code
  to find a scratch directory on Android and a web-native path on web,
  verified end-to-end on both.

## [1.1.4] - 2026-09-18

### Added
- Row Lines screen: a manual row line can now be deleted individually — a
  small red delete button appears at each row's midpoint in Manual mode,
  removing just that one row without needing to reset and regenerate every
  row from the guide line.

### Fixed
- Manually dragging a row line's endpoint sideways (Row Lines screen) could
  still make the row cross a neighboring row somewhere along its length,
  even though the endpoint itself never crossed the neighbor's matching
  endpoint — most visible on tapering fields, where the diagonal connecting
  a moved endpoint to the row's fixed other end could slice through a
  neighboring row in the middle. The drag now checks the whole line for an
  actual crossing and holds at the last valid position instead of letting
  it pass through.
- Report's Area Covered % (and the completion percentage derived from it)
  used a fixed, plot-wide row-spacing tolerance for every row corridor and
  reset instantly on a single stray GPS reading — the same flat-tolerance,
  no-tapering-support, no-jitter-tolerance issues already fixed in the
  Monitoring/Report coverage heatmap display, just not carried over to this
  calculation. It now mirrors the same fixed logic (each corridor's
  tolerance from its own real current gap, tapering support, and a few
  consecutive readings needed before crediting a genuine row change), so
  Area Covered % stays accurate on tapering fields and after a row line is
  manually edited or deleted. *(backend)*
- A device registered twice with its MAC address in different letter case
  (e.g. `d4:…` and `D4:…`) made the firmware update check fail with
  "Device did not respond" — the backend crashed on the duplicate match and
  the reply never reached the app. A device whose MAC was stored in a
  different case than the one it transmits with could also silently record
  no sessions, GPS track, or reports at all, while still appearing Online.
  MAC addresses are now stored uppercase (existing ones are normalized on
  deploy; any pair that is still a true duplicate is left untouched and
  logged for manual cleanup), and the OTA handlers no longer crash if a
  duplicate is ever found. *(backend)*

## [1.1.3] - 2026-09-17

### Added
- **Investor Dashboard** — new aggregate, all-customers fleet dashboard at
  `/investor-dashboard/`, meant to be pulled up live during investor
  pitches: hero KPIs (area sprayed, spray volume applied, chemical saved,
  devices deployed), fleet growth/traction charts, fleet health and
  firmware-version distribution, spray-efficiency and coverage
  distributions, operating cadence, and a live fleet map showing each
  device's real GPS position — sourced from its own telemetry (a pulsing
  marker while a session is actively transmitting, falling back to its
  last-known fix or plot location when idle). Sign-in required; a new
  investor-viewer account type can see only this dashboard and nothing
  else admin-shaped — no Django admin, no other admin API. *(backend)*
- **Public landing page** at `/` — a marketing/product page open to
  anyone, no login required, separate from both the app and the
  sign-in-gated Investor Dashboard it links to. *(backend)*
- Report Details' "Additional Details" card now has a third editable field,
  Agrochemical, alongside Driver Name and Fertilizers Used — free-text,
  defaults to "N/A" until filled in, editable any time after the report is
  generated. *(backend)*

### Fixed
- Report's Avg Flow Rate (L/min and L/acre) could show 0.00 despite a real,
  nonzero Total Sprayed figure if the sprayer device rebooted near the end
  of a session — it was calculated from the tank sensor's final reading
  minus its initial reading, and that sensor's counter resets to ~0 on a
  device reboot, so a reboot right before the session ended could zero out
  the whole calculation even though the flow sensor had correctly recorded
  real spraying. Now calculated from the same accumulated total already
  shown in Total Sprayed (which isn't affected by a reboot), so it always
  reflects the real average. *(backend)*
- Left Sol. Off / Right Sol. Off could show 0.00 even when the report's
  Left/Right heatmap visibly showed spraying gaps — Left/Right Spray
  Distance was accumulating distance whenever a solenoid read as on, even
  during PTO-off stretches (e.g. headland turns), which could push it past
  PTO On Dist. itself and make the Off calculation go negative and get
  silently hidden as 0.00. Left/Right Spray Distance is now only counted
  while PTO is on, matching how PTO On Dist. itself is tracked. *(backend)*
- Investor Dashboard's live fleet map showed OpenStreetMap's "403 Access
  blocked" tile error instead of the map — OSM's tile server actively
  blocks embedded web apps that hit it directly without a distinguishing
  User-Agent (which browser JS can't set on tile requests), so this was
  never going to load reliably. Switched to the same Google tile source
  already used everywhere else in the app (Monitoring, Report Details,
  Plot Mapping). *(backend)*
- Control Unit setup screen's measurement captions (distance between sensor
  and nozzle center, LIDAR mount height, ultrasonic sensor distance) were
  bolder than the input field below them and could clip on small phone
  screens — now normal weight, matching the rest of the form.
- Sprayer and Tractor/Equipment setup screens' hinge-distance labels
  (hinge→axle, hinge→nozzle, hinge→control unit mounting) could get cut off
  on small phone screens — the full description now wraps as a caption
  above the field, with a short "Distance" label inside the field itself.
- Coverage heatmap (GPS, Speed, and Left/Right views on Monitoring and
  Report Details) could show small gaps along a row the sprayer drove
  continuously — ordinary GPS jitter of a couple of metres, worse with
  tight row spacing, was enough to momentarily read as just outside the
  row and break the paint job at that exact spot. The same issue affected
  the red "outside the plot" boundary track. Both now tolerate a few
  consecutive stray readings before treating it as a real exit.
- Coverage heatmap could scatter one continuous pass down a single row
  across several neighboring columns instead — most noticeable on fields
  with wide or tapering row spacing, where ordinary GPS jitter could read
  as fractionally closer to a neighboring row for an isolated reading. The
  heatmap now credits one row per continuous pass and only switches once
  several consecutive readings genuinely agree on a different row.
- Manually dragging a row line's endpoint (Row Lines screen) could stretch
  or shrink the row, or drag it past a neighboring row entirely — either
  could silently corrupt the heatmap's row-width calculation for that area
  of the field. An endpoint now stays locked to the row's original length
  when dragged (it can still angle sideways, e.g. to match a real tapering
  field) and can never cross past a neighboring row.

## [1.1.2] - 2026-08-31

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
- Device now gets an MQTT message on a new `/<device_id>/boundary` topic
  when it crosses the plot boundary (`{"outside": true/false}`), same
  push pattern as the existing `/config` topic — lets the firmware react
  to a geofence breach itself, not just the app's Monitoring screen
  notification. *(backend)*

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
- Deleting a ControlUnit or Report left zero trace of who did it or when
  — DELETE requests hard-delete with no audit trail, and Django's admin
  log only covers actions taken in the admin site, not the regular API.
  New AuditLog now records user/timestamp/what was deleted for both
  endpoints, viewable (read-only) in Django admin. *(backend)*
- A completed report's plot name/polygon/map link/snapshot image could
  silently change after the fact if the control unit was later reassigned
  to a different plot (e.g. while its just-ended session was still in
  cooldown) — these were re-resolved live from the control unit's current
  plot on every view instead of being fixed at report time. The plot's
  data is now frozen into the report the moment it's generated, so
  reassigning a control unit's plot afterward never alters an existing
  report. *(backend)*

### Security
- Login no longer prints the incoming email/password pair to the server
  console on every attempt — a leftover debug `print()` was logging
  plaintext passwords into container logs (and from there, Loki/Grafana).
  *(backend)*

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
