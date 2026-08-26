import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'ws_channel_stub.dart'
    if (dart.library.io) 'ws_channel_io.dart'
    if (dart.library.html) 'ws_channel_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/mac_utils.dart';
import 'api_service.dart';
import 'auth_service.dart' show apiServiceProvider;

/// Possible device lifecycle states driven by backend WebSocket events.
enum DeviceLifecycleStatus {
  online,
  cooldown,  // offline_pending_report — report generating, countdown running
  offline,
}

/// Holds the current cooldown / status state for one device.
/// Emitted via [TelemetryService.deviceCooldownStream].
class CooldownState {
  final String deviceId;
  final DeviceLifecycleStatus status;

  /// When the cooldown ends (null when not in cooldown).
  final DateTime? cooldownEnd;

  /// 'manual_end' | 'auto_timeout' | null
  final String? cooldownType;

  /// DB session id (from report_ready event)
  final int? sessionId;

  /// DB report id (available after report_ready)
  final int? reportId;

  const CooldownState({
    required this.deviceId,
    required this.status,
    this.cooldownEnd,
    this.cooldownType,
    this.sessionId,
    this.reportId,
  });

  bool get isInCooldown => status == DeviceLifecycleStatus.cooldown;

  /// Remaining seconds until cooldown ends. Returns 0 when not in cooldown.
  int get secondsRemaining {
    if (cooldownEnd == null) return 0;
    final diff = cooldownEnd!.difference(DateTime.now().toUtc()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  /// Human-readable MM:SS countdown string.
  String get countdownLabel {
    final s = secondsRemaining;
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  CooldownState copyWith({
    DeviceLifecycleStatus? status,
    DateTime? cooldownEnd,
    String? cooldownType,
    int? sessionId,
    int? reportId,
  }) {
    return CooldownState(
      deviceId: deviceId,
      status: status ?? this.status,
      cooldownEnd: cooldownEnd ?? this.cooldownEnd,
      cooldownType: cooldownType ?? this.cooldownType,
      sessionId: sessionId ?? this.sessionId,
      reportId: reportId ?? this.reportId,
    );
  }

  @override
  String toString() =>
      'CooldownState($deviceId, $status, end=$cooldownEnd, type=$cooldownType)';
}

/// OTA firmware update progress/terminal status (RFC-004), emitted via
/// [TelemetryService.deviceOtaStatusStream]. Mirrors the states published on
/// the device's /<id>/ota/status MQTT topic 1:1 — see
/// smart-spray-backend/docs/RFC-004-OTA-Firmware-Update.md §6 for the full
/// state machine this drives.
class OtaStatusEvent {
  final String deviceId;
  final String state; // WIFI_CONNECTING | IN_PROGRESS | DOWNLOAD_OK | SUCCESS | FAILED | ROLLBACK
  final int? code;
  // IN_PROGRESS: percent (int, 0-100). SUCCESS/ROLLBACK: version (String).
  // FAILED: human-readable reason (String).
  final dynamic detail;

  const OtaStatusEvent({
    required this.deviceId,
    required this.state,
    this.code,
    this.detail,
  });

  int? get progressPercent => state == 'IN_PROGRESS' && detail is num
      ? (detail as num).toInt()
      : null;

  String? get reason => state == 'FAILED' && detail is String ? detail as String : null;

  String? get resultingVersion =>
      (state == 'SUCCESS' || state == 'ROLLBACK') && detail != null
          ? detail.toString()
          : null;

  @override
  String toString() => 'OtaStatusEvent($deviceId, $state, code=$code, detail=$detail)';
}

/// Reply to a ["GET"] version query on /<id>/ota/version, emitted via
/// [TelemetryService.deviceOtaVersionStatusStream].
class OtaVersionStatusEvent {
  final String deviceId;
  final String? liveVersion;

  const OtaVersionStatusEvent({required this.deviceId, this.liveVersion});
}

class TelemetryData {
  final String deviceId;
  final DateTime timestamp;
  final int? gpsSignalQuality;
  final int? simSignalQuality;
  final double? lat;
  final double? lon;
  final double? leftDistance;
  final double? rightDistance;
  final double? leftDensity;
  final double? rightDensity;
  final double? speed;
  final double? flowRate;
  final int? leftSolenoidState;
  final int? rightSolenoidState;
  final int? sprayMode;
  final double? tankLevel;
  final int? ptoState;
  final double? jobCompletionPercent;
  final String? plot;
  final bool? deviceInPlot;
  final double? flowRateLpm;
  final double? flowInLitres;

  TelemetryData({
    required this.deviceId,
    required this.timestamp,
    this.gpsSignalQuality,
    this.simSignalQuality,
    this.lat,
    this.lon,
    this.leftDistance,
    this.rightDistance,
    this.leftDensity,
    this.rightDensity,
    this.speed,
    this.flowRate,
    this.leftSolenoidState,
    this.rightSolenoidState,
    this.sprayMode,
    this.tankLevel,
    this.ptoState,
    this.jobCompletionPercent,
    this.plot,
    this.deviceInPlot,
    this.flowRateLpm,
    this.flowInLitres,
  });

  /// Parse telemetry JSON. Returns null when required fields (device_id
  /// and a parseable timestamp) are missing to avoid treating malformed
  /// messages as "active" (previously defaulted to now).
  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    // device id (support multiple common keys)
    final rawId = json['device_id'] ??
        json['deviceId'] ??
        json['id'] ??
        json['mac'] ??
        json['mac_address'];
    final deviceId = rawId?.toString().trim() ?? '';
    if (deviceId.isEmpty) throw FormatException('missing device_id');

    DateTime? ts;
    // try multiple common timestamp keys
    final cand = json['timestamp'] ?? json['ts'] ?? json['time'] ?? json['t'];
    if (cand != null) {
      // accept numeric epoch (seconds or milliseconds) or ISO strings
      try {
        if (cand is num) {
          // cand may be int or double
          final n = cand.toDouble();
          final ms = n > 1000000000000 ? n.toInt() : (n * 1000).toInt();
          ts = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
        } else {
          final s = cand.toString();
          // try parse as a floating numeric string first (e.g. "1763401570.0")
          final asNum = double.tryParse(s);
          if (asNum != null) {
            final ms =
                asNum > 1000000000000 ? asNum.toInt() : (asNum * 1000).toInt();
            ts = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
          } else {
            // fallback to ISO date parsing; treat parsed instants as UTC
            try {
              final parsed = DateTime.parse(s);
              ts = parsed.toUtc();
            } catch (_) {
              ts = null;
            }
          }
        }
      } catch (_) {
        ts = null;
      }
    }
    if (ts == null) {
      if (json['status'] == 'offline') {
        ts = DateTime.now().toUtc();
      } else {
        throw FormatException('invalid timestamp');
      }
    }

    return TelemetryData(
      deviceId: deviceId,
      timestamp: ts,
      gpsSignalQuality: json['gps_signal_quality'] is int
          ? json['gps_signal_quality']
          : (json['gps_signal_quality'] != null
              ? int.tryParse(json['gps_signal_quality'].toString())
              : null),
      simSignalQuality: json['sim_signal_quality'] is int
          ? json['sim_signal_quality']
          : (json['sim_signal_quality'] != null
              ? int.tryParse(json['sim_signal_quality'].toString())
              : null),
      lat: json['lat'] is num ? (json['lat'] as num).toDouble() : null,
      lon: json['lon'] is num ? (json['lon'] as num).toDouble() : null,
      leftDistance: json['left_distance'] is num
          ? (json['left_distance'] as num).toDouble()
          : null,
      rightDistance: json['right_distance'] is num
          ? (json['right_distance'] as num).toDouble()
          : null,
      leftDensity: json['left_density'] is num
          ? (json['left_density'] as num).toDouble()
          : null,
      rightDensity: json['right_density'] is num
          ? (json['right_density'] as num).toDouble()
          : null,
      speed: json['speed'] is num ? (json['speed'] as num).toDouble() : null,
      flowRate: json['flow_rate'] is num
          ? (json['flow_rate'] as num).toDouble()
          : null,
      leftSolenoidState: json['left_solenoid_state'] is int
          ? json['left_solenoid_state']
          : (json['left_solenoid_state'] != null
              ? int.tryParse(json['left_solenoid_state'].toString())
              : null),
      rightSolenoidState: json['right_solenoid_state'] is int
          ? json['right_solenoid_state']
          : (json['right_solenoid_state'] != null
              ? int.tryParse(json['right_solenoid_state'].toString())
              : null),
      sprayMode: json['spray_mode'] is int
          ? json['spray_mode']
          : (json['spray_mode'] != null
              ? int.tryParse(json['spray_mode'].toString())
              : null),
      tankLevel: json['tank_level'] is num
          ? (json['tank_level'] as num).toDouble()
          : null,
      ptoState: json['pto_state'] is int
          ? json['pto_state']
          : (json['pto_state'] != null
              ? int.tryParse(json['pto_state'].toString())
              : null),
      jobCompletionPercent: json['job_completion_percent'] is num
          ? (json['job_completion_percent'] as num).toDouble()
          : null,
      plot: json['plot']?.toString(),
      deviceInPlot: json['device_in_plot'] is bool
          ? json['device_in_plot'] as bool
          : (json['device_in_plot'] != null
              ? (json['device_in_plot'].toString().toLowerCase() == 'true' ||
                  json['device_in_plot'].toString() == '1')
              : null),
      flowRateLpm: json['flow_rate_lpm'] is num
          ? (json['flow_rate_lpm'] as num).toDouble()
          : null,
      flowInLitres: json['flow_in_litres'] is num
          ? (json['flow_in_litres'] as num).toDouble()
          : null,
    );
  }
}

class TelemetryService {
  TelemetryService({required this.baseUrl, ApiService? apiService})
      : _apiService = apiService {
    _startPruner();
  }

  final String baseUrl;

  // Used only by [reconcileCooldownState] to fetch backend truth as a
  // fallback when a WebSocket status_change/report_ready event is missed.
  // Nullable so existing callers/tests that construct TelemetryService
  // without an ApiService keep working unchanged (reconcile just no-ops).
  final ApiService? _apiService;

  // Map deviceId -> last telemetry
  final Map<String, TelemetryData> _latest = {};
  // active channels keyed by normalized (lowercase) device id
  final Map<String, WebSocketChannel> _channels = {};
  // desired subscriptions set (normalized ids) - used for reconnect logic
  final Set<String> _desiredSubscriptions = {};
  // simple reconnect attempt counters per device
  final Map<String, int> _reconnectAttempts = {};

  final _activeController = StreamController<List<TelemetryData>>.broadcast();
  Stream<List<TelemetryData>> get activeDevicesStream =>
      _activeController.stream;

  // Broadcast stream of all telemetry updates as they arrive. Consumers can
  // filter this stream for a particular device id to get live updates.
  final _updatesController = StreamController<TelemetryData>.broadcast();

  // ── Cooldown / lifecycle state ──────────────────────────────────────────
  // Per-device cooldown state driven by backend WS status events.
  final Map<String, CooldownState> _cooldownStates = {};

  // Last time telemetry was received per device. Not cleared by the pruner —
  // only cleared when the session actually ends (status_change / report_ready)
  // or on unsubscribe/clearCache. Used to show a "waiting" countdown on the UI
  // during the backend idle window (sessionTimeoutMinutes) before session
  // auto-timeout.
  final Map<String, DateTime> _lastSeenAt = {};

  // Last known job_completion_percent per device. Not cleared by the pruner so
  // the monitoring screen can show the correct coverage % even when the device
  // is temporarily offline (latestTelemetry is null). Cleared on session end.
  final Map<String, double> _lastKnownCoverage = {};

  /// Idle minutes before the backend auto-ends a session
  /// (mirrors jobs/session_service.py's WATCHDOG_TIMEOUT_MINUTES — keep in sync).
  static const int sessionTimeoutMinutes = 60;

  // Broadcast stream that emits a CooldownState whenever any device's
  // lifecycle status changes (status_change or report_ready events).
  final _cooldownController = StreamController<CooldownState>.broadcast();

  /// Stream of CooldownState changes for [deviceId].
  Stream<CooldownState> deviceCooldownStream(String deviceId) {
    final norm = canonicalizeMac(deviceId);
    return _cooldownController.stream
        .where((s) => canonicalizeMac(s.deviceId) == norm);
  }

  /// Get the last known CooldownState for [deviceId], or null if unknown.
  CooldownState? getCooldownState(String deviceId) {
    return _cooldownStates[canonicalizeMac(deviceId)];
  }

  // ── OTA firmware update (RFC-004) ───────────────────────────────────────
  final _otaStatusController = StreamController<OtaStatusEvent>.broadcast();
  final _otaVersionStatusController =
      StreamController<OtaVersionStatusEvent>.broadcast();

  /// Stream of OTA progress/terminal status events for [deviceId]. The
  /// Firmware Update Workspace screen drives its whole state machine off
  /// this — same demux pattern as [deviceCooldownStream], just a third
  /// branch on the WebSocket's `type` field (see telemetry/consumers.py's
  /// `ota_status` handler on the backend).
  Stream<OtaStatusEvent> deviceOtaStatusStream(String deviceId) {
    final norm = canonicalizeMac(deviceId);
    return _otaStatusController.stream
        .where((e) => canonicalizeMac(e.deviceId) == norm);
  }

  /// Stream of version-query replies for [deviceId] (backend's
  /// `ota_version_status` WS event) — used by the Firmware Update
  /// Workspace's initial handshake to show the live hardware version.
  Stream<OtaVersionStatusEvent> deviceOtaVersionStatusStream(String deviceId) {
    final norm = canonicalizeMac(deviceId);
    return _otaVersionStatusController.stream
        .where((e) => canonicalizeMac(e.deviceId) == norm);
  }

  /// Last time telemetry was received from [deviceId].
  /// Returns null if no telemetry has been received or the session has ended.
  DateTime? getLastSeenAt(String deviceId) =>
      _lastSeenAt[canonicalizeMac(deviceId)];

  /// Last known job_completion_percent for [deviceId].
  /// Persists even when device is temporarily offline (not cleared by pruner).
  /// Returns null if no coverage has been received or the session has ended.
  double? getLastKnownCoverage(String deviceId) =>
      _lastKnownCoverage[canonicalizeMac(deviceId)];

  /// In-memory history of positions per device (normalized device id -> list
  /// of timestamped lat/lon entries). Kept in memory for the app lifetime.
  /// Each entry now also stores the PTO state and whether device was in-plot
  /// at the time so consumers can render point-level status.
  final Map<String, List<_LatLonEntry>> _positions = {};

  Timer? _pruneTimer;

  // Number of seconds to consider telemetry 'fresh' and therefore "online".
  // Device sends a packet roughly every ~2s, so 8s gives a ~4-packet buffer
  // for normal network jitter while still flipping to WAITING almost
  // immediately once the device actually stops sending (previously 60s,
  // which made the Active Devices list look like it was lagging far behind
  // the Monitoring screen, which clears its live marker on the same signal).
  static const int _activeThresholdSeconds = 8;

  void _startPruner() {
    _pruneTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().toUtc();
      final actives = <TelemetryData>[];
      
      // Determine which IDs to remove
      final toRemove = <String>[];
      _latest.forEach((k, v) {
        // Use receive time (v.timestamp) for active check.
        final diff = now.difference(v.timestamp.toUtc()).inSeconds;
        if (diff <= _activeThresholdSeconds) {
          actives.add(v);
        } else {
          toRemove.add(k);
        }
      });

      // Remove stale live snapshot only — GPS history (_positions) is kept
      // until the session actually ends (status_change / report_ready event).
      // This ensures the track remains visible if the device temporarily stops.
      for (final id in toRemove) {
        debugPrint('Telemetry.pruner: $id is offline - clearing live snapshot (history preserved)');
        _latest.remove(id);
      }

      _activeController.add(actives);
    });
  }

  /// Subscribe to telemetry websocket for [deviceId] (MAC address string).
  /// If already subscribed, this is a no-op.
  void subscribe(String deviceId) {
    final normKey = canonicalizeMac(deviceId);
    // record as desired subscription
    _desiredSubscriptions.add(normKey);
    // if already have a channel, nothing to do
    if (_channels.containsKey(normKey)) return;
    try {
      // Server expects the device id in the websocket URL to be uppercase
      // (case-sensitive). Internally we use a normalized lowercase key
      // (`normKey`) for maps, but construct the URL with the uppercase id.
      final url = '$baseUrl/ws/telemetry/${normKey.toUpperCase()}/';
      debugPrint(
          'Telemetry: attempting WebSocket connect to $url (norm=$normKey)');
      late final WebSocketChannel channel;
      try {
        debugPrint('Telemetry: connecting to $url via platform wrapper');
        channel = connectWebSocket(url);
      } catch (e) {
        debugPrint('Telemetry: websocket connect failed for $url: $e');
        rethrow;
      }
      // store channel under normalized key so unsubscribe works reliably
      _channels[normKey] = channel;
      // reset reconnect attempts on successful subscribe
      _reconnectAttempts[normKey] = 0;
      debugPrint('Telemetry: subscribed to $url (norm=$normKey)');
      channel.stream.listen((message) {
        try {
          // log raw message string for easier debugging
          debugPrint('Telemetry raw (string) for $deviceId: ${message.toString()}');

          Map<String, dynamic> data = (message is String)
              ? json.decode(message) as Map<String, dynamic>
              : (json.decode(utf8.decode(message)) as Map<String, dynamic>);

          // Unwrap envelope if present (Django Channels/Bridge adds these)
          try {
            Map<String, dynamic>? inner;
            if (data.containsKey('data')) {
              final d = data['data'];
              if (d is String) {
                try {
                  inner = json.decode(d) as Map<String, dynamic>;
                } catch (_) {}
              } else if (d is Map) {
                inner = Map<String, dynamic>.from(d);
              }
            }
            if (inner == null && data.containsKey('payload')) {
              final d = data['payload'];
              if (d is String) {
                try {
                  inner = json.decode(d) as Map<String, dynamic>;
                } catch (_) {}
              } else if (d is Map) {
                inner = Map<String, dynamic>.from(d);
              }
            }
            if (inner == null && data.containsKey('message')) {
              final d = data['message'];
              if (d is String) {
                try {
                  inner = json.decode(d) as Map<String, dynamic>;
                } catch (_) {}
              } else if (d is Map) {
                inner = Map<String, dynamic>.from(d);
              }
            }
            if (inner != null) data = inner;
          } catch (e) {
            debugPrint('Telemetry: envelope unwrap error: $e');
          }

          // ── Handle lifecycle status events BEFORE telemetry parsing ──────
          // These arrive as top-level messages (no data envelope) with a
          // 'type' field set to 'status_change' or 'report_ready'.
          final msgType = data['type']?.toString();

          if (msgType == 'status_change') {
            final rawId = data['device_id']?.toString() ?? deviceId;
            final normId = canonicalizeMac(rawId);
            final endTs = data['cooldown_end_ts'];
            DateTime? cooldownEnd;
            if (endTs != null) {
              final asNum = endTs is num
                  ? endTs.toDouble()
                  : double.tryParse(endTs.toString());
              if (asNum != null && asNum > 0) {
                final ms = asNum > 1e12
                    ? asNum.toInt()
                    : (asNum * 1000).toInt();
                cooldownEnd =
                    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
              }
            }
            final state = CooldownState(
              deviceId: rawId,
              status: DeviceLifecycleStatus.cooldown,
              cooldownEnd: cooldownEnd,
              cooldownType: data['cooldown_type']?.toString(),
            );
            _cooldownStates[normId] = state;
            _cooldownController.add(state);
            // Remove from active tracking immediately; subsequent telemetry
            // from the still-running hardware is suppressed below.
            _latest.remove(normId);
            _positions.remove(normId);
            _lastSeenAt.remove(normId);
            _lastKnownCoverage.remove(normId);
            if (normKey != normId) {
              _latest.remove(normKey);
              _positions.remove(normKey);
              _lastSeenAt.remove(normKey);
              _lastKnownCoverage.remove(normKey);
            }
            _activeController.add(getActiveDevices());
            debugPrint('Telemetry: status_change for $normId → cooldown until $cooldownEnd');
            return;
          }

          if (msgType == 'report_ready') {
            final rawId = data['device_id']?.toString() ?? deviceId;
            final normId = canonicalizeMac(rawId);
            final state = CooldownState(
              deviceId: rawId,
              status: DeviceLifecycleStatus.offline,
              sessionId: data['session_id'] is int
                  ? data['session_id'] as int
                  : int.tryParse(data['session_id']?.toString() ?? ''),
              reportId: data['report_id'] is int
                  ? data['report_id'] as int
                  : int.tryParse(data['report_id']?.toString() ?? ''),
            );
            _cooldownStates[normId] = state;
            _cooldownController.add(state);
            // Only wipe the live snapshot and position history if the device
            // is not already sending fresh telemetry (i.e. a new session has
            // not already started). If report_ready arrives late — after the
            // device came back online — clearing _latest would cause a brief
            // deviceOnlineProvider=false flash and erase new-session positions.
            final alreadyActive = _latest.containsKey(normId);
            if (!alreadyActive) {
              _latest.remove(normId);
              _positions.remove(normId);
              _lastSeenAt.remove(normId);
              _lastKnownCoverage.remove(normId);
              _activeController.add(getActiveDevices());
            }
            debugPrint('Telemetry: report_ready for $normId — '
                '${alreadyActive ? "new session already active, positions preserved" : "device fully offline"}');
            return;
          }

          // ── OTA firmware update events (RFC-004) ──────────────────────────
          // Same top-level, no-envelope shape as status_change/report_ready
          // above — see telemetry/consumers.py's ota_status/ota_version_status
          // handlers on the backend.
          if (msgType == 'ota_status') {
            final rawId = data['device_id']?.toString() ?? deviceId;
            _otaStatusController.add(OtaStatusEvent(
              deviceId: rawId,
              state: data['state']?.toString() ?? '',
              code: data['code'] is int
                  ? data['code'] as int
                  : int.tryParse(data['code']?.toString() ?? ''),
              detail: data['detail'],
            ));
            return;
          }

          if (msgType == 'ota_version_status') {
            final rawId = data['device_id']?.toString() ?? deviceId;
            _otaVersionStatusController.add(OtaVersionStatusEvent(
              deviceId: rawId,
              liveVersion: data['live_version']?.toString(),
            ));
            return;
          }

          // Handle explicit offline status (legacy path — keep for compatibility)
          if (data['status'] == 'offline' && msgType == null) {
            final offId = canonicalizeMac(data['device_id'] ?? deviceId);
            debugPrint('Telemetry: explicit offline for $offId - clearing cache');
            _latest.remove(offId);
            _positions.remove(offId);
            _lastSeenAt.remove(offId);
            _activeController.add(getActiveDevices());
            return;
          }

          TelemetryData t;
          try {
            t = TelemetryData.fromJson(data);
          } catch (e) {
            debugPrint('Telemetry: parse failed: $e. Data: $data');
            return;
          }

          final normId = canonicalizeMac(t.deviceId);

          // Suppress telemetry from hardware that keeps sending during cooldown.
          final cs = _cooldownStates[normId];
          if (cs != null && cs.status == DeviceLifecycleStatus.cooldown) {
            debugPrint('Telemetry: suppressing $normId — device is in cooldown');
            return;
          }
          // Fresh telemetry after fully offline means a new session started.
          // Clear the cooldown state AND broadcast an `online` event so any
          // UI subscribed via `deviceCooldownStream` (e.g. the Active Devices
          // list) learns the device is no longer offline. Without this
          // broadcast the StreamProvider keeps its last cached `offline`
          // value and the device stays stuck on "OFFLINE" even though
          // active telemetry is flowing.
          if (cs != null && cs.status == DeviceLifecycleStatus.offline) {
            _cooldownStates.remove(normId);
            _cooldownController.add(CooldownState(
              deviceId: cs.deviceId,
              status: DeviceLifecycleStatus.online,
            ));
          }

          final now = DateTime.now().toUtc();
          final age = now.difference(t.timestamp.toUtc()).inSeconds;
          debugPrint('Telemetry.received subscription=$normKey payload=$normId age=${age}s');

          // Use the local receive time (not the device clock) for the active
          // threshold check. The device clock can drift or be unsynchronised,
          // which would cause the pruner to immediately remove the device from
          // the active list even though data just arrived.
          final stored = TelemetryData(
            deviceId: normId,
            timestamp: DateTime.now().toUtc(), // receive time — not device clock
            gpsSignalQuality: t.gpsSignalQuality,
            simSignalQuality: t.simSignalQuality,
            lat: t.lat,
            lon: t.lon,
            leftDistance: t.leftDistance,
            rightDistance: t.rightDistance,
            leftDensity: t.leftDensity,
            rightDensity: t.rightDensity,
            speed: t.speed,
            flowRate: t.flowRate,
            leftSolenoidState: t.leftSolenoidState,
            rightSolenoidState: t.rightSolenoidState,
            sprayMode: t.sprayMode,
            tankLevel: t.tankLevel,
            ptoState: t.ptoState,
            jobCompletionPercent: t.jobCompletionPercent,
            plot: t.plot,
            deviceInPlot: t.deviceInPlot,
            flowRateLpm: t.flowRateLpm,
            flowInLitres: t.flowInLitres,
          );

          _latest[normId] = stored;
          _lastSeenAt[normId] = DateTime.now().toUtc();
          if (stored.jobCompletionPercent != null) {
            _lastKnownCoverage[normId] = stored.jobCompletionPercent!;
          }

          // Also mark the subscription key as active
          if (normKey != normId) {
            _latest[normKey] = stored;
            _lastSeenAt[normKey] = DateTime.now().toUtc();
            if (stored.jobCompletionPercent != null) {
              _lastKnownCoverage[normKey] = stored.jobCompletionPercent!;
            }
          }

          // Positional history
          if (stored.lat != null && stored.lon != null) {
            final lat = stored.lat!;
            final lon = stored.lon!;
            if (lat.abs() > 0.1 || lon.abs() > 0.1) {
              final list = _positions.putIfAbsent(normId, () => []);
              list.add(_LatLonEntry(
                timestamp: stored.timestamp.toUtc(),
                lat: lat,
                lon: lon,
                speed: stored.speed,
                flowRate: stored.flowRate,
                sprayMode: stored.sprayMode,
                ptoState: stored.ptoState,
                deviceInPlot: stored.deviceInPlot,
              ));
            }
          }

          _updatesController.add(stored);
          _activeController.add(getActiveDevices());
        } catch (e) {
          debugPrint('Telemetry error for $deviceId: $e');
        }
      }, onError: (err) {
        debugPrint('Telemetry websocket error for $deviceId: $err');
      }, onDone: () {
        _channels.remove(normKey);
        debugPrint('Telemetry websocket closed for $deviceId');
        final attempts = (_reconnectAttempts[normKey] ?? 0) + 1;
        _reconnectAttempts[normKey] = attempts;
        if (_desiredSubscriptions.contains(normKey)) {
          // Cap backoff at 30 s; no attempt limit — always reconnect so
          // lifecycle events (report_ready, status_change) are never missed.
          final delay = Duration(seconds: (1 << (attempts - 1)).clamp(1, 30));
          debugPrint('Telemetry: reconnecting $normKey in ${delay.inSeconds}s (attempt $attempts)');
          Timer(delay, () {
            if (_desiredSubscriptions.contains(normKey) && !_channels.containsKey(normKey)) {
              subscribe(normKey);
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Telemetry subscribe error for $deviceId: $e');
    }
  }

  void unsubscribe(String deviceId) {
    final norm = canonicalizeMac(deviceId);
    // mark as not desired
    _desiredSubscriptions.remove(norm);
    final ch = _channels.remove(norm);
    ch?.sink.close();
    _latest.remove(norm);
    _lastSeenAt.remove(norm);
    _lastKnownCoverage.remove(norm);
    _reconnectAttempts.remove(norm);
  }

  /// Manually push a [CooldownState] into the shared cache and broadcast it,
  /// without waiting for the backend's WebSocket `status_change` event.
  ///
  /// Used for optimistic UI updates (e.g. when the user taps "End Device" on
  /// the monitoring screen) so that OTHER screens watching this device via
  /// [deviceCooldownStream] / [getCooldownState] (like the Active Devices
  /// list) reflect the cooldown immediately too, instead of only updating
  /// once the real server event arrives.
  void setCooldownStateOptimistic(CooldownState state) {
    final norm = canonicalizeMac(state.deviceId);
    final normalized = CooldownState(
      deviceId: norm,
      status: state.status,
      cooldownEnd: state.cooldownEnd,
      cooldownType: state.cooldownType,
      sessionId: state.sessionId,
      reportId: state.reportId,
    );
    _cooldownStates[norm] = normalized;
    _cooldownController.add(normalized);
  }

  /// Reconcile the cached [CooldownState] for [rawMac] against the backend's
  /// live Redis state (`GET /jobs/api/devices/<mac>/status/`).
  ///
  /// The cooldown badge/timer is normally driven purely by pushed WebSocket
  /// events (`status_change`, `report_ready`). Pub/sub delivery is
  /// fire-and-forget — if the app is backgrounded or the socket drops for a
  /// few seconds at the exact moment one of those events fires, it's gone
  /// for good and the cached state is stuck showing a stale cooldown
  /// forever (seen in production: badge frozen on "Cooldown" with a dead
  /// timer, while a brand new session was already active in the DB).
  ///
  /// Call this whenever a screen that shows device status mounts/resumes.
  /// It only *corrects* an out-of-date cache — it never fights a WS event
  /// that already agrees, and any failure (offline, 404, auth) is swallowed
  /// silently so a flaky network never disrupts the live WS-driven UI this
  /// sits alongside.
  Future<void> reconcileCooldownState(String rawMac) async {
    final api = _apiService;
    if (api == null || rawMac.trim().isEmpty) return;
    final norm = canonicalizeMac(rawMac);

    try {
      final path = '/jobs/api/devices/${Uri.encodeComponent(rawMac)}/status/';
      final data = await api.getJson(path);
      if (data is! Map) return;

      final statusStr = data['status']?.toString() ?? 'offline';
      final DeviceLifecycleStatus backendStatus;
      switch (statusStr) {
        case 'online':
          backendStatus = DeviceLifecycleStatus.online;
          break;
        case 'offline_pending_report':
          backendStatus = DeviceLifecycleStatus.cooldown;
          break;
        default:
          backendStatus = DeviceLifecycleStatus.offline;
      }

      DateTime? cooldownEnd;
      final endTs = data['cooldown_end_ts'];
      if (endTs != null) {
        final asNum =
            endTs is num ? endTs.toDouble() : double.tryParse(endTs.toString());
        if (asNum != null && asNum > 0) {
          final ms = asNum > 1e12 ? asNum.toInt() : (asNum * 1000).toInt();
          cooldownEnd = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
        }
      }

      final cached = _cooldownStates[norm];
      // Cache already agrees with the backend — nothing to correct, and
      // skipping avoids a redundant stream event on every screen mount.
      if (cached != null &&
          cached.status == backendStatus &&
          cached.cooldownEnd == cooldownEnd) {
        return;
      }

      final reconciled = CooldownState(
        deviceId: rawMac,
        status: backendStatus,
        cooldownEnd: cooldownEnd,
        cooldownType: data['cooldown_type']?.toString(),
        sessionId: data['session_id'] is int
            ? data['session_id'] as int
            : int.tryParse(data['session_id']?.toString() ?? ''),
      );
      _cooldownStates[norm] = reconciled;
      _cooldownController.add(reconciled);
      debugPrint(
          'Telemetry: reconciled $norm from status endpoint (was ${cached?.status}) → $backendStatus');
    } catch (e) {
      debugPrint('Telemetry: reconcileCooldownState failed for $rawMac: $e');
    }
  }

  /// Restore this device's GPS track from the backend's persisted history
  /// (`GET /jobs/api/devices/<mac>/gps_points/`), replacing whatever partial
  /// or empty local `_positions` list we currently have.
  ///
  /// The live track is normally built up purely from WebSocket pushes held
  /// in memory — nothing is persisted on the phone. If the app is
  /// backgrounded, Android can either kill the process outright (wiping the
  /// in-memory track entirely) or just drop the WebSocket for a while
  /// (leaving a gap that shows up as the track "jumping" once it
  /// reconnects). The backend keeps every point for the active session in
  /// Postgres regardless of whether the app is open, so re-fetching it here
  /// makes the track whole again instead of missing or jumping.
  ///
  /// Call this whenever a screen showing the live track mounts/resumes.
  /// Fire-and-forget safe: any failure (offline, 404, auth) is swallowed
  /// silently so a flaky network never disrupts the live WS-driven UI.
  Future<void> restoreTrackFromBackend(String rawMac) async {
    final api = _apiService;
    if (api == null || rawMac.trim().isEmpty) return;
    final norm = canonicalizeMac(rawMac);

    try {
      final path = '/jobs/api/devices/${Uri.encodeComponent(rawMac)}/gps_points/';
      final data = await api.getJson(path);
      if (data is! Map) return;

      final rawPoints = data['points'];
      if (rawPoints is! List || rawPoints.isEmpty) return;

      final restored = <_LatLonEntry>[];
      for (final p in rawPoints) {
        if (p is! Map) continue;
        final lat = (p['lat'] as num?)?.toDouble();
        final lon = (p['lon'] as num?)?.toDouble();
        final ts = DateTime.tryParse(p['timestamp']?.toString() ?? '');
        if (lat == null || lon == null || ts == null) continue;
        restored.add(_LatLonEntry(
          timestamp: ts.toUtc(),
          lat: lat,
          lon: lon,
          speed: (p['speed_kmph'] as num?)?.toDouble(),
          flowRate: (p['flow_rate_lpm'] as num?)?.toDouble(),
          sprayMode: (p['spray_mode'] as num?)?.toInt(),
          ptoState: (p['pto_state'] as num?)?.toInt(),
          deviceInPlot: p['device_in_plot'] as bool?,
        ));
      }
      if (restored.isEmpty) return;

      // Backend is authoritative for this session's track — replace rather
      // than merge/append, so a killed-and-restarted app doesn't end up with
      // duplicate points once live WS updates resume.
      _positions[norm] = restored;
      debugPrint(
          'Telemetry: restored ${restored.length} GPS points for $norm from backend');
    } catch (e) {
      debugPrint('Telemetry: restoreTrackFromBackend failed for $rawMac: $e');
    }
  }

  /// Manually clear the cached telemetry for a device.
  void clearCache(String deviceId) {
    final norm = canonicalizeMac(deviceId);
    debugPrint('Telemetry: Manually clearing cache for $norm');
    _latest.remove(norm);
    _positions.remove(norm);
    _lastSeenAt.remove(norm);
    _lastKnownCoverage.remove(norm);
    _activeController.add(getActiveDevices());
  }

  /// Subscribe to a set of device IDs and ensure only those are kept subscribed.
  /// Normalizes IDs (trim+lower) and will unsubscribe any channels not in [deviceIds].
  void subscribeToDevices(List<String> deviceIds) {
    debugPrint('Telemetry.subscribeToDevices called with: $deviceIds');
    final normIds = deviceIds
        .map((d) => canonicalizeMac(d))
        .where((d) => d.isNotEmpty)
        .toSet();
    // update desired subscriptions
    _desiredSubscriptions
      ..clear()
      ..addAll(normIds);
    debugPrint('Telemetry.subscribeToDevices normalized to: $normIds');
    // subscribe missing
    for (final id in normIds) {
      if (!_channels.containsKey(id)) {
        subscribe(id);
      }
    }
    // unsubscribe extras
    final toRemove = _channels.keys.where((k) => !normIds.contains(k)).toList();
    for (final k in toRemove) {
      unsubscribe(k);
    }
  }

  /// Get a list of currently active device telemetry (timestamp within 3s)
  List<TelemetryData> getActiveDevices() {
    final now = DateTime.now().toUtc();
    return _latest.values
        .where((v) =>
            now.difference(v.timestamp.toUtc()).inSeconds <=
            _activeThresholdSeconds)
        .toList();
  }

  /// Debug: list of currently subscribed (normalized) device ids
  List<String> get subscribedDeviceIds => _channels.keys.toList();

  /// Debug: snapshot of latest telemetry map (deviceId -> TelemetryData)
  Map<String, TelemetryData> get latestTelemetry =>
      Map<String, TelemetryData>.from(_latest);

  /// Return a copy of the stored positions (lat/lon history) for [deviceId].
  List<Map<String, dynamic>> getPositions(String deviceId) {
    final norm = canonicalizeMac(deviceId);
    final list = _positions[norm] ?? <_LatLonEntry>[];
    return list
        .map((e) => <String, dynamic>{
              'timestamp': e.timestamp.toIso8601String(),
              'lat': e.lat,
              'lon': e.lon,
              'speed': e.speed,
              'flow_rate': e.flowRate,
              'spray_mode': e.sprayMode,
              'pto': e.ptoState,
              'device_in_plot': e.deviceInPlot,
            })
        .toList();
  }

  /// Stream of live TelemetryData updates for a particular device id.
  Stream<TelemetryData> deviceTelemetryStream(String deviceId) {
    final norm = canonicalizeMac(deviceId);
    return _updatesController.stream
        .where((t) => canonicalizeMac(t.deviceId) == norm);
  }

  void dispose() {
    for (final ch in _channels.values) {
      ch.sink.close();
    }
    _channels.clear();
    _latest.clear();
    _pruneTimer?.cancel();
    _positions.clear();
    _lastSeenAt.clear();
    _lastKnownCoverage.clear();
    _cooldownStates.clear();
    try {
      _updatesController.close();
    } catch (_) {}
    try {
      _activeController.close();
    } catch (_) {}
    try {
      _cooldownController.close();
    } catch (_) {}
    try {
      _otaStatusController.close();
    } catch (_) {}
    try {
      _otaVersionStatusController.close();
    } catch (_) {}
  }
}

/// Small internal type for storing timestamped lat/lon history.
class _LatLonEntry {
  final DateTime timestamp;
  final double lat;
  final double lon;
  final double? speed;
  final double? flowRate;
  final int? sprayMode;
  final int? ptoState;
  final bool? deviceInPlot;
  _LatLonEntry({
    required this.timestamp,
    required this.lat,
    required this.lon,
    this.speed,
    this.flowRate,
    this.sprayMode,
    this.ptoState,
    this.deviceInPlot,
  });
}

final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  // Use provided base URL; default to ws://13.201.0.34:8001
  final svc = TelemetryService(
    baseUrl: 'ws://3.108.218.140:8001',
    apiService: ref.watch(apiServiceProvider),
  );
  ref.onDispose(() => svc.dispose());
  return svc;
});

final activeDevicesProvider = StreamProvider<List<TelemetryData>>((ref) {
  final svc = ref.watch(telemetryServiceProvider);
  return svc.activeDevicesStream;
});

final deviceOnlineProvider = Provider.family<bool, String>((ref, deviceId) {
  final actives = ref.watch(activeDevicesProvider).asData?.value ?? [];
  final norm = canonicalizeMac(deviceId);
  return actives.any((a) => canonicalizeMac(a.deviceId) == norm);
});

/// Provides a stream of [CooldownState] changes for a specific device.
///
/// Emits whenever the backend sends a `status_change` or `report_ready`
/// WebSocket event for [deviceId].  The stream is seeded with the last
/// known state so screens that mount after an event immediately reflect
/// the current cooldown.
final deviceCooldownStateProvider =
    StreamProvider.family<CooldownState, String>((ref, deviceId) {
  final svc = ref.watch(telemetryServiceProvider);

  Stream<CooldownState> seeded() async* {
    final existing = svc.getCooldownState(deviceId);
    if (existing != null) yield existing;
    yield* svc.deviceCooldownStream(deviceId);
  }

  return seeded();
});
