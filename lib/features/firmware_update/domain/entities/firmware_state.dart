/// UI-level stages for the Firmware Update Workspace screen (RFC-004 §6).
///
/// These map onto the backend's `OtaStatusEvent.state` values (WIFI_CONNECTING,
/// IN_PROGRESS, DOWNLOAD_OK, SUCCESS, FAILED, ROLLBACK) plus a few UI-only
/// stages (idle / waitingToConnect / wifiRequired / locked) that don't exist
/// on the wire but are needed to drive the screen.
enum FirmwareUpdateStage {
  idle,
  waitingToConnect,
  wifiRequired, // FAILED 401 — show SSID/password inputs
  wifiTimeout, // FAILED 408 — inline error, re-enable inputs
  downloading, // IN_PROGRESS
  verifying, // DOWNLOAD_OK — 90s countdown
  success,
  rollback,
  connectionLost, // FAILED 504 — modal, re-show Update button
  criticalFailure, // 507/413/422/404/403/503/400/other-HTTP
  locked, // server-side 504 lockout (RFC-004 §2.2.1) still active
}

/// One row from GET /api/admin/firmware-alerts/ — backs the Alerts tab in
/// admin_dashboard_screen.dart (RFC-004 §2.3/§4.5, the "Central Admin Panel"
/// for critical OTA failures / rollbacks).
class FirmwareAlertEntity {
  final int id;
  final String controlUnitName;
  final String? macAddr;
  final String? owner;
  final int statusCode;
  final String reason;
  final DateTime createdAt;
  final bool resolved;

  const FirmwareAlertEntity({
    required this.id,
    required this.controlUnitName,
    this.macAddr,
    this.owner,
    required this.statusCode,
    required this.reason,
    required this.createdAt,
    required this.resolved,
  });

  factory FirmwareAlertEntity.fromJson(Map<String, dynamic> json) {
    return FirmwareAlertEntity(
      id: json['id'] as int,
      controlUnitName: json['control_unit_name'] as String? ?? 'Unknown device',
      macAddr: json['mac_addr'] as String?,
      owner: json['owner'] as String?,
      statusCode: json['status_code'] as int? ?? 0,
      reason: json['reason'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      resolved: json['resolved'] as bool? ?? false,
    );
  }
}

/// Snapshot for the version handshake (RFC-004 §3): DB version, S3
/// available version, and (once queried) the live hardware version.
class FirmwareVersionSnapshot {
  final String dbVersion;
  final String? availableVersion;
  final String? liveVersion;
  final int? lockedForSeconds;
  // Backend-persisted OTA status (RFC-004 §2.1's firmware_status/_progress_percent)
  // and the latest attempt's failure detail — the resync path a stuck screen
  // falls back on if a WebSocket status event is ever missed (e.g. app briefly
  // lost its socket mid-update on a real network).
  final String? backendStatus;
  final int? backendProgressPercent;
  final int? latestAttemptStatusCode;
  final String? latestAttemptReason;

  const FirmwareVersionSnapshot({
    required this.dbVersion,
    this.availableVersion,
    this.liveVersion,
    this.lockedForSeconds,
    this.backendStatus,
    this.backendProgressPercent,
    this.latestAttemptStatusCode,
    this.latestAttemptReason,
  });

  bool get updateAvailable =>
      availableVersion != null && availableVersion != dbVersion;

  FirmwareVersionSnapshot copyWith({
    String? liveVersion,
    int? lockedForSeconds,
  }) {
    return FirmwareVersionSnapshot(
      dbVersion: dbVersion,
      availableVersion: availableVersion,
      liveVersion: liveVersion ?? this.liveVersion,
      lockedForSeconds: lockedForSeconds ?? this.lockedForSeconds,
      backendStatus: backendStatus,
      backendProgressPercent: backendProgressPercent,
      latestAttemptStatusCode: latestAttemptStatusCode,
      latestAttemptReason: latestAttemptReason,
    );
  }
}
