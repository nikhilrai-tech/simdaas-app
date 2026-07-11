import '../../domain/entities/firmware_state.dart';
import '../datasources/firmware_remote_data_source.dart';

class FirmwareRepositoryImpl {
  final FirmwareRemoteDataSource remote;
  FirmwareRepositoryImpl(this.remote);

  Future<FirmwareVersionSnapshot> getStatus(String controlUnitId) =>
      remote.getStatus(controlUnitId);

  Future<void> requestCheckVersion(String controlUnitId) =>
      remote.requestCheckVersion(controlUnitId);

  Future<void> startUpdate(String controlUnitId, {required String targetVersion}) =>
      remote.startUpdate(controlUnitId, targetVersion: targetVersion);

  Future<void> sendWifiCredentials(String controlUnitId,
          {required String ssid, required String password}) =>
      remote.sendWifiCredentials(controlUnitId, ssid: ssid, password: password);

  Future<List<FirmwareAlertEntity>> getAdminAlerts() => remote.getAdminAlerts();
}
