import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/telemetry_service.dart';
import '../../data/datasources/equipment_remote_data_source.dart';
import '../../data/repositories/equipment_repository_impl.dart';
import '../../domain/entities/equipment.dart';

final equipmentRepoProvider = Provider((ref) => EquipmentRepositoryImpl(
    EquipmentRemoteDataSourceImpl(ref.read(apiServiceProvider))));

final equipmentsListProvider =
    FutureProvider.family<List<EquipmentEntity>, String>((ref, userId) async {
  // Ensure auth is initialized so the token is set on ApiService
  await ref.read(authServiceProvider).initialized;
  final repo = ref.read(equipmentRepoProvider);
  return repo.getEquipments(userId);
});

// Dedicated category providers to avoid fetching all equipment when only one
// category is required.
final tractorsProvider =
    FutureProvider.family<List<EquipmentEntity>, String>((ref, userId) async {
  await ref.read(authServiceProvider).initialized;
  final repo = ref.read(equipmentRepoProvider);
  return repo.getTractors(userId);
});

final sprayersProvider =
    FutureProvider.family<List<EquipmentEntity>, String>((ref, userId) async {
  await ref.read(authServiceProvider).initialized;
  final repo = ref.read(equipmentRepoProvider);
  return repo.getSprayers(userId);
});

final controlUnitsProvider =
    FutureProvider.family<List<EquipmentEntity>, String>((ref, userId) async {
  await ref.read(authServiceProvider).initialized;
  final repo = ref.read(equipmentRepoProvider);
  return repo.getControlUnits(userId);
});

final equipmentControllerProvider = Provider((ref) => EquipmentController(ref));

class EquipmentController {
  final Ref ref;
  EquipmentController(this.ref);

  Future<void> add(Map<String, dynamic> data) async {
    final repo = ref.read(equipmentRepoProvider);
    await repo.addEquipment(data);
    // After adding, invalidate equipment providers so UI lists refresh.
    final currentUserId =
        ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    ref.invalidate(equipmentsListProvider(currentUserId));
    final category = (data['category'] as String?)?.toLowerCase();
    switch (category) {
      case 'control_unit':
        ref.invalidate(controlUnitsProvider(currentUserId));
        break;
      case 'sprayer':
        ref.invalidate(sprayersProvider(currentUserId));
        break;
      case 'tractor':
        ref.invalidate(tractorsProvider(currentUserId));
        break;
      default:
        break;
    }
  }

  Future<void> update(String id, Map<String, dynamic> data) async {
    final repo = ref.read(equipmentRepoProvider);
    await repo.updateEquipment(id, data);
    // After updating, invalidate equipment providers so UI lists refresh.
    final currentUserId =
        ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    ref.invalidate(equipmentsListProvider(currentUserId));
    final category = (data['category'] as String?)?.toLowerCase();
    switch (category) {
      case 'control_unit':
        ref.invalidate(controlUnitsProvider(currentUserId));
        break;
      case 'sprayer':
        ref.invalidate(sprayersProvider(currentUserId));
        break;
      case 'tractor':
        ref.invalidate(tractorsProvider(currentUserId));
        break;
      default:
        break;
    }
  }

  Future<void> delete(String id, {String? category}) async {
    final repo = ref.read(equipmentRepoProvider);
    await repo.deleteEquipment(id, category: category);
    // After deleting, invalidate equipment providers so UI lists refresh.
    final currentUserId =
        ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    ref.invalidate(equipmentsListProvider(currentUserId));
    final cat = (category ?? '').toLowerCase();
    switch (cat) {
      case 'control_unit':
        ref.invalidate(controlUnitsProvider(currentUserId));
        break;
      case 'sprayer':
        ref.invalidate(sprayersProvider(currentUserId));
        break;
      case 'tractor':
        ref.invalidate(tractorsProvider(currentUserId));
        break;
      default:
        break;
    }
  }

  /// Ends a session from the app.
  ///
  /// Returns `true` when the backend closed it right away (Automatic devices:
  /// a cooldown starts). Returns `false` when it only *requested* the stop
  /// (Manual devices): the sprayer closes its own session, so nothing is
  /// cleared locally — the app waits for the `session_event` / `report_ready`
  /// that follows. `force` closes a Manual session on the server when the
  /// device can't be reached.
  Future<bool> endSession(int sessionId,
      {String? deviceId, bool force = false, String? pin}) async {
    final repo = ref.read(equipmentRepoProvider);
    final result = await repo.endSession(sessionId, force: force, pin: pin);
    final requestedOnly = result['status'] == 'requested';

    if (!requestedOnly && deviceId != null) {
      ref.read(telemetryServiceProvider).clearCache(deviceId);
    }

    final currentUserId =
        ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    ref.invalidate(equipmentsListProvider(currentUserId));
    ref.invalidate(controlUnitsProvider(currentUserId));
    return !requestedOnly;
  }

  /// Switches a control unit between Automatic (`server`) and Manual
  /// (`device`) session mode. Throws an [ApiException] whose body carries a
  /// stable `code` (session_active / firmware_unsupported / feature_disabled).
  Future<void> setSessionMode(String controlUnitId, {required String mode}) async {
    final repo = ref.read(equipmentRepoProvider);
    await repo.setSessionMode(controlUnitId, mode: mode);
    final currentUserId =
        ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    ref.invalidate(equipmentsListProvider(currentUserId));
    ref.invalidate(controlUnitsProvider(currentUserId));
  }

  /// Virtual start button (Manual mode). The session appears once the device confirms.
  Future<void> startDeviceSession(String mac, {String? pin}) async {
    await ref.read(equipmentRepoProvider).startDeviceSession(mac, pin: pin);
  }

  /// Virtual stop button (Manual mode). The session ends when the device confirms.
  Future<void> stopDeviceSession(String mac, {String? pin}) async {
    await ref.read(equipmentRepoProvider).stopDeviceSession(mac, pin: pin);
  }

  Future<void> pushDemoConfig(String id, {required bool demo}) async {
    final repo = ref.read(equipmentRepoProvider);
    await repo.pushDemoConfig(id, demo: demo);
  }
}
