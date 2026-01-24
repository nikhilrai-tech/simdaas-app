import 'package:flutter/foundation.dart';
import 'package:simdaas/core/services/api_service.dart';
import '../models/equipment_model.dart';
import '../../domain/entities/equipment.dart';

abstract class EquipmentRemoteDataSource {
  Future<void> addEquipment(Map<String, dynamic> data);
  Future<void> updateEquipment(String id, Map<String, dynamic> data);
  Future<void> deleteEquipment(String id, {String? category});
  Future<List<EquipmentEntity>> getEquipments(String userId);
  Future<List<EquipmentEntity>> getTractors(String userId);
  Future<List<EquipmentEntity>> getSprayers(String userId);
  Future<List<EquipmentEntity>> getControlUnits(String userId);
}

class EquipmentRemoteDataSourceImpl implements EquipmentRemoteDataSource {
  final ApiService api;
  EquipmentRemoteDataSourceImpl(this.api);

  @override
  Future<void> addEquipment(Map<String, dynamic> data) async {
    // Transform UI camelCase data into snake_case payloads expected by backend
    final category = data['category'] as String? ?? 'equipments';
    final userId = data['userId'] ?? data['user_id'];

    if (category == 'tractor') {
      final bodyMap = <String, dynamic>{};
      bodyMap['name'] = data['name'];
      if (userId != null) {
        final parsed = int.tryParse(userId.toString());
        bodyMap['user_id'] = parsed ?? userId;
        bodyMap['user'] = parsed ?? userId;
      }
      if (data['wheelDiameter'] != null) {
        final wd = data['wheelDiameter'];
        bodyMap['wheel_diameter'] =
            wd is String ? (double.tryParse(wd) ?? wd) : wd;
      }
      if (data['screwsInWheel'] != null) {
        bodyMap['screws_per_wheel'] = data['screwsInWheel'];
      }
      if (data['axleLength'] != null) {
        bodyMap['axle_length'] = data['axleLength'].toString();
      }
      if (data['contactNumber'] != null) {
        bodyMap['contact_number'] = data['contactNumber'];
      }

      await api.postJson('/api/tractors/', jsonBody: bodyMap);
      return;
    } else if (category == 'sprayer') {
      final bodyMap = <String, dynamic>{};
      bodyMap['name'] = data['name'];
      if (userId != null) {
        final parsed = int.tryParse(userId.toString());
        bodyMap['user_id'] = parsed ?? userId;
        bodyMap['user'] = parsed ?? userId;
      }
      // optional fields - only include when provided
      if (data['nozzleCount'] != null) {
        final nc = data['nozzleCount'];
        bodyMap['nozzle_count'] =
            nc is String ? (double.tryParse(nc) ?? nc) : nc;
      }
      if (data['tankCapacity'] != null) {
        bodyMap['tank_capacity'] = data['tankCapacity'];
      }
      if (data['wheelDiameter'] != null) {
        bodyMap['wheel_diameter'] = data['wheelDiameter'].toString();
      }
      if (data['screwsInWheel'] != null) {
        bodyMap['screws_per_wheel'] = data['screwsInWheel'];
      }
      if (data['axleLength'] != null) {
        bodyMap['axle_length'] = data['axleLength'].toString();
      }
      if (data['hingeToAxle'] != null) {
        bodyMap['distance_hinge_axle'] = data['hingeToAxle'].toString();
      }
      if (data['hingeToNozzle'] != null) {
        bodyMap['distance_hinge_nozzle'] = data['hingeToNozzle'].toString();
      }
      if (data['hingeToControlUnit'] != null) {
        bodyMap['distance_hinge_control_unit'] =
            data['hingeToControlUnit'].toString();
      }

      await api.postJson('/api/sprayers/', jsonBody: bodyMap);
      return;
    } else if (category == 'control_unit') {
      final bodyMap = <String, dynamic>{};
      bodyMap['name'] = data['name'];
      // link to user if provided
      if (userId != null) {
        final parsed = int.tryParse(userId.toString());
        bodyMap['user_id'] = parsed ?? userId;
        bodyMap['user'] = parsed ?? userId;
      }
      if (data['linkedPlotId'] != null) {
        final p = int.tryParse(data['linkedPlotId'].toString());
        if (p != null) bodyMap['plot'] = p;
      }
      if (data['macAddress'] != null) bodyMap['mac_addr'] = data['macAddress'];
      // backend expects sprayer/tractor as primitive ids
      if (data['linkedSprayerId'] != null) {
        final p = int.tryParse(data['linkedSprayerId'].toString());
        if (p != null) bodyMap['sprayer'] = p;
      }
      if (data['linkedPlotId'] != null) {
        final p = int.tryParse(data['linkedPlotId'].toString());
        if (p != null) bodyMap['plot'] = p;
      }
      if (data['linkedTractorId'] != null) {
        final p = int.tryParse(data['linkedTractorId'].toString());
        if (p != null) bodyMap['tractor'] = p;
      }
      if (data['lidarNozzleDistance'] != null) {
        bodyMap['distance_b_w_sensor_and_nozzle_center'] =
            data['lidarNozzleDistance'];
      }
      if (data['mountingHeight'] != null) {
        bodyMap['mount_height_of_lidar'] = data['mountingHeight'];
      }
      if (data['ultrasonicDistance'] != null) {
        bodyMap['distance_of_us_sensor_from_center_line'] =
            data['ultrasonicDistance'];
      }

      await api.postJson('/api/control-units/', jsonBody: bodyMap);
      return;
    }

    // Fallback: generic equipments endpoint - send whatever we have
    await api.postJson('/api/equipments/', jsonBody: data);
  }

  @override
  Future<void> updateEquipment(String id, Map<String, dynamic> data) async {
    // Mirror the add transformation for updates
    final category = data['category'] as String? ?? 'equipments';
    final userId = data['userId'] ?? data['user_id'];

    if (category == 'tractor') {
      final bodyMap = <String, dynamic>{};
      if (data.containsKey('name')) bodyMap['name'] = data['name'];
      if (userId != null) {
        final parsed = int.tryParse(userId.toString());
        bodyMap['user_id'] = parsed ?? userId;
        bodyMap['user'] = parsed ?? userId;
      }
      if (data['wheelDiameter'] != null) {
        bodyMap['wheel_diameter'] = data['wheelDiameter'];
      }
      if (data['screwsInWheel'] != null) {
        bodyMap['screws_per_wheel'] = data['screwsInWheel'];
      }
      if (data['axleLength'] != null) {
        bodyMap['axle_length'] = data['axleLength'].toString();
      }
      if (data['contactNumber'] != null) {
        bodyMap['contact_number'] = data['contactNumber'];
      }

      // Use PATCH for partial updates
      await api.patchJson('/api/tractors/$id/', jsonBody: bodyMap);
      return;
    } else if (category == 'sprayer') {
      final bodyMap = <String, dynamic>{};
      if (data.containsKey('name')) bodyMap['name'] = data['name'];
      if (userId != null) {
        final parsed = int.tryParse(userId.toString());
        bodyMap['user_id'] = parsed ?? userId;
        bodyMap['user'] = parsed ?? userId;
      }
      if (data['nozzleCount'] != null) {
        bodyMap['nozzle_count'] = data['nozzleCount'];
      }
      if (data['tankCapacity'] != null) {
        bodyMap['tank_capacity'] = data['tankCapacity'];
      }
      if (data['wheelDiameter'] != null) {
        bodyMap['wheel_diameter'] = data['wheelDiameter'].toString();
      }
      if (data['screwsInWheel'] != null) {
        bodyMap['screws_per_wheel'] = data['screwsInWheel'];
      }
      if (data['axleLength'] != null) {
        bodyMap['axle_length'] = data['axleLength'].toString();
      }
      if (data['hingeToAxle'] != null) {
        bodyMap['distance_hinge_axle'] = data['hingeToAxle'].toString();
      }
      if (data['hingeToNozzle'] != null) {
        bodyMap['distance_hinge_nozzle'] = data['hingeToNozzle'].toString();
      }
      if (data['hingeToControlUnit'] != null) {
        bodyMap['distance_hinge_control_unit'] =
            data['hingeToControlUnit'].toString();
      }

      // Use PATCH for partial updates
      await api.patchJson('/api/sprayers/$id/', jsonBody: bodyMap);
      return;
    }

    // control_unit updates
    if (category == 'control_unit') {
      final bodyMap = <String, dynamic>{};
      if (data.containsKey('name')) bodyMap['name'] = data['name'];
      if (userId != null) {
        final parsed = int.tryParse(userId.toString());
        bodyMap['user_id'] = parsed ?? userId;
        bodyMap['user'] = parsed ?? userId;
      }
      if (data.containsKey('macAddress')) {
        bodyMap['mac_addr'] = data['macAddress'];
      }
      // Respect explicit presence of keys even when null so callers can clear
      // links by sending `linkedSprayerId: null` etc.
      if (data.containsKey('linkedSprayerId')) {
        final raw = data['linkedSprayerId'];
        if (raw == null) {
          bodyMap['sprayer'] = null;
        } else {
          final p = int.tryParse(raw.toString());
          if (p != null) bodyMap['sprayer'] = p;
        }
      }
      if (data.containsKey('linkedTractorId')) {
        final raw = data['linkedTractorId'];
        if (raw == null) {
          bodyMap['tractor'] = null;
        } else {
          final p = int.tryParse(raw.toString());
          if (p != null) bodyMap['tractor'] = p;
        }
      }
      debugPrint("linkedPlotId check-----------------------------");
      debugPrint(data.toString());
      if (data.containsKey('linkedPlotId')) {
        final raw = data['linkedPlotId'];
        if (raw == null) {
          bodyMap['plot'] = null;
        } else {
          final p = int.tryParse(raw.toString());
          if (p != null) bodyMap['plot'] = p;
        }
      }
      if (data.containsKey('lidarNozzleDistance')) {
        bodyMap['distance_b_w_sensor_and_nozzle_center'] =
            data['lidarNozzleDistance'];
      }
      if (data.containsKey('mountingHeight')) {
        bodyMap['mount_height_of_lidar'] = data['mountingHeight'];
      }
      if (data.containsKey('ultrasonicDistance')) {
        bodyMap['distance_of_us_sensor_from_center_line'] =
            data['ultrasonicDistance'];
      }

      // Debug: log outgoing payload for easier troubleshooting
      debugPrint('PATCH /api/control-units/$id/ payload: $bodyMap');
      // Use PATCH for partial updates
      await api.patchJson('/api/control-units/$id/', jsonBody: bodyMap);
      return;
    }

    // Fallback: use PATCH for partial update on generic endpoint
    await api.patchJson('/api/equipments/$id/', jsonBody: data);
  }

  @override
  Future<void> deleteEquipment(String id, {String? category}) async {
    // Use category-specific endpoint when available to avoid backend 404s
    if (category == 'tractor') {
      await api.delete('/api/tractors/$id/');
      return;
    }
    if (category == 'sprayer') {
      await api.delete('/api/sprayers/$id/');
      return;
    }
    if (category == 'control_unit') {
      await api.delete('/api/control-units/$id/');
      return;
    }
    await api.delete('/api/equipments/$id/');
  }

  @override
  Future<List<EquipmentEntity>> getEquipments(String userId) async {
    // Merge tractors and sprayers lists
    final List<EquipmentEntity> out = [];
    final arrT = (await api.getJson('/api/tractors/')) as List<dynamic>;
    for (final item in arrT) {
      final map = Map<String, dynamic>.from(item as Map);
      final id = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
      final normalized = Map<String, dynamic>.from(map);
      normalized['category'] = 'tractor';
      out.add(EquipmentModel.fromJson(id, normalized));
    }
    final arrS = (await api.getJson('/api/sprayers/')) as List<dynamic>;
    for (final item in arrS) {
      final map = Map<String, dynamic>.from(item as Map);
      final id = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
      final normalized = Map<String, dynamic>.from(map);
      normalized['category'] = 'sprayer';
      out.add(EquipmentModel.fromJson(id, normalized));
    }
    // control units
    try {
      final arrC = (await api.getJson('/api/control-units/')) as List<dynamic>;
      for (final item in arrC) {
        final map = Map<String, dynamic>.from(item as Map);
        final id = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
        final normalized = Map<String, dynamic>.from(map);
        normalized['category'] = 'control_unit';
        out.add(EquipmentModel.fromJson(id, normalized));
      }
    } catch (e, st) {
      // If control-units endpoint isn't present or returns unexpected data,
      // log the error for diagnostics and continue with tractors/sprayers list.
      debugPrint(
          'EquipmentRemoteDataSource.getEquipments: control-units parse error: $e');
      debugPrint('stack: $st');
    }
    return out;
  }

  @override
  Future<List<EquipmentEntity>> getTractors(String userId) async {
    final List<EquipmentEntity> out = [];
    final arr = (await api.getJson('/api/tractors/')) as List<dynamic>;
    for (final item in arr) {
      final map = Map<String, dynamic>.from(item as Map);
      final id = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
      final normalized = Map<String, dynamic>.from(map);
      normalized['category'] = 'tractor';
      out.add(EquipmentModel.fromJson(id, normalized));
    }
    return out;
  }

  @override
  Future<List<EquipmentEntity>> getSprayers(String userId) async {
    final List<EquipmentEntity> out = [];
    final arr = (await api.getJson('/api/sprayers/')) as List<dynamic>;
    for (final item in arr) {
      final map = Map<String, dynamic>.from(item as Map);
      final id = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
      final normalized = Map<String, dynamic>.from(map);
      normalized['category'] = 'sprayer';
      out.add(EquipmentModel.fromJson(id, normalized));
    }
    return out;
  }

  @override
  Future<List<EquipmentEntity>> getControlUnits(String userId) async {
    try {
      debugPrint(
          'EquipmentRemoteDataSource: GET /api/control-units/ (userId=$userId)');
      final List<EquipmentEntity> out = [];
      final arr = (await api.getJson('/api/control-units/')) as List<dynamic>;
      for (final item in arr) {
        final map = Map<String, dynamic>.from(item as Map);
        final id = (map['id']?.toString() ?? map['pk']?.toString() ?? '');
        final normalized = Map<String, dynamic>.from(map);
        normalized['category'] = 'control_unit';
        out.add(EquipmentModel.fromJson(id, normalized));
      }
      return out;
    } catch (e, st) {
      debugPrint('EquipmentRemoteDataSource.getControlUnits: error: $e');
      debugPrint('EquipmentRemoteDataSource.getControlUnits: stack: $st');
      rethrow;
    }
  }
}
