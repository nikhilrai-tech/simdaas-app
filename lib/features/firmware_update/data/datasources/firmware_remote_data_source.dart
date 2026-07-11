import 'package:simdaas/core/services/api_service.dart';
import '../../domain/entities/firmware_state.dart';

abstract class FirmwareRemoteDataSource {
  Future<FirmwareVersionSnapshot> getStatus(String controlUnitId);
  Future<void> requestCheckVersion(String controlUnitId);
  Future<void> startUpdate(String controlUnitId, {required String targetVersion});
  Future<void> sendWifiCredentials(String controlUnitId,
      {required String ssid, required String password});
  Future<List<FirmwareAlertEntity>> getAdminAlerts();
}

class FirmwareRemoteDataSourceImpl implements FirmwareRemoteDataSource {
  final ApiService api;
  FirmwareRemoteDataSourceImpl(this.api);

  @override
  Future<FirmwareVersionSnapshot> getStatus(String controlUnitId) async {
    final json = await api.getJson('/api/control-units/$controlUnitId/firmware/')
        as Map<String, dynamic>;
    return FirmwareVersionSnapshot(
      dbVersion: json['db_version'] as String? ?? '1.0.0',
      availableVersion: json['available_version'] as String?,
      lockedForSeconds: json['locked_for_seconds'] as int?,
      backendStatus: json['status'] as String?,
      backendProgressPercent: json['progress_percent'] as int?,
      latestAttemptStatusCode: json['latest_attempt_status_code'] as int?,
      latestAttemptReason: json['latest_attempt_reason'] as String?,
    );
  }

  @override
  Future<void> requestCheckVersion(String controlUnitId) async {
    await api.postJson('/api/control-units/$controlUnitId/firmware/check-version/');
  }

  @override
  Future<void> startUpdate(String controlUnitId, {required String targetVersion}) async {
    // 423 (locked) surfaces as an ApiException — the caller (provider) reads
    // e.body for retry_after_seconds. Never log the request/response bodies
    // for this endpoint's sibling (/wifi/) — see RFC-004 §3.5.
    await api.postJson(
      '/api/control-units/$controlUnitId/firmware/update/',
      jsonBody: {'target_version': targetVersion},
    );
  }

  @override
  Future<void> sendWifiCredentials(String controlUnitId,
      {required String ssid, required String password}) async {
    await api.postJson(
      '/api/control-units/$controlUnitId/firmware/wifi/',
      jsonBody: {'ssid': ssid, 'password': password},
    );
  }

  @override
  Future<List<FirmwareAlertEntity>> getAdminAlerts() async {
    final json = await api.getJson('/api/admin/firmware-alerts/') as List<dynamic>;
    return json
        .map((e) => FirmwareAlertEntity.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
