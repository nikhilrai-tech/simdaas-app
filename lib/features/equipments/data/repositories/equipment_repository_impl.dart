import '../../domain/entities/equipment.dart';
import '../datasources/equipment_remote_data_source.dart';
// ...existing code...

class EquipmentRepositoryImpl {
  final EquipmentRemoteDataSource remote;
  EquipmentRepositoryImpl(this.remote);

  Future<void> addEquipment(Map<String, dynamic> data) =>
      remote.addEquipment(data);
  Future<void> updateEquipment(String id, Map<String, dynamic> data) =>
      remote.updateEquipment(id, data);
  Future<void> deleteEquipment(String id, {String? category}) =>
      remote.deleteEquipment(id, category: category);
  Future<List<EquipmentEntity>> getEquipments(String userId) =>
      remote.getEquipments(userId);
  Future<List<EquipmentEntity>> getTractors(String userId) =>
      remote.getTractors(userId);
  Future<List<EquipmentEntity>> getSprayers(String userId) =>
      remote.getSprayers(userId);
  Future<List<EquipmentEntity>> getControlUnits(String userId) =>
      remote.getControlUnits(userId);
  Future<Map<String, dynamic>> endSession(int sessionId, {bool force = false}) =>
      remote.endSession(sessionId, force: force);
  Future<Map<String, dynamic>> setSessionMode(String controlUnitId, {required String mode, String? pin}) =>
      remote.setSessionMode(controlUnitId, mode: mode, pin: pin);
  Future<Map<String, dynamic>> startDeviceSession(String mac) => remote.startDeviceSession(mac);
  Future<Map<String, dynamic>> stopDeviceSession(String mac) => remote.stopDeviceSession(mac);
  Future<void> pushDemoConfig(String id, {required bool demo}) =>
      remote.pushDemoConfig(id, demo: demo);
  Future<String> getDemoConfigStatus(String id) =>
      remote.getDemoConfigStatus(id);
}
