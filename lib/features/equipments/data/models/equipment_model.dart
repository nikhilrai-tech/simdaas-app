import '../../domain/entities/equipment.dart';

class EquipmentModel extends EquipmentEntity {
  EquipmentModel({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.mountingHeight,
    super.lidarNozzleDistance,
    super.ultrasonicDistance,
    super.wheelDiameter,
    super.screwsInWheel,
    super.axleLength,
    super.nozzleCount,
    super.tankCapacity,
    super.hingeToAxle,
    super.hingeToNozzle,
    super.hingeToControlUnit,
    super.macAddress,
    super.linkedSprayerId,
    super.linkedTractorId,
    super.linkedPlotId,
    super.activeSessionId,
    super.firmwareVersion,
    super.firmwareAvailableVersion,
    super.rightFrontOffset,
    super.rightBackOffset,
    super.leftFrontOffset,
    super.leftBackOffset,
    super.flowPulseCount,
    super.lastSeenAt,
    super.createdAt,
    super.updatedAt,
  });

  factory EquipmentModel.fromJson(String id, Map<String, dynamic> json) {
    // helper to read either snake_case or camelCase numeric fields
    double? readNum(String a, [String? b]) =>
        (json[a] as num?)?.toDouble() ??
        (b != null ? (json[b] as num?)?.toDouble() : null);
    int? readInt(String a, [String? b]) =>
        (json[a] as num?)?.toInt() ??
        (b != null ? (json[b] as num?)?.toInt() : null);

    /// Robustly extract ID from a field that could be:
    /// 1. A single Map with an 'id' key
    /// 2. A List containing a Map with an 'id' key (backend mismatch fix)
    /// 3. A primitive value (String/int)
    String? _extractId(dynamic val) {
      if (val == null) return null;
      if (val is List && val.isNotEmpty) {
        final first = val.first;
        if (first is Map && first.containsKey('id')) {
          return first['id'].toString();
        }
      } else if (val is Map && val.containsKey('id')) {
        return val['id'].toString();
      } else if (val is! Map && val is! List) {
        return val.toString();
      }
      return null;
    }

    // user id may be provided as userId/ownerId or as nested user object
    String? userId = json['userId'] as String? ?? json['ownerId'] as String?;
    if (userId == null && json['user'] is Map) {
      final u = json['user'] as Map<String, dynamic>;
      userId = u['id'] != null
          ? u['id'].toString()
          : (u['user'] as String? ?? u['username'] as String?);
    }

    final category = (json['category'] as String? ?? '').toString();
    // parse timestamps with snake_case fallback
    DateTime? parseTime(String a, [String? b]) {
      final v = json[a] ?? (b != null ? json[b] : null);
      return v != null ? DateTime.tryParse(v.toString()) : null;
    }

    if (category == 'tractor') {
      return TractorModel(
        id: id,
        category: category,
        name: json['name'] as String? ?? '',
        userId: json['user'].toString() as String? ?? userId,
        status: json['status'] as String?,
        mountingHeight: readNum('mountingHeight', 'mounting_height'),
        lidarNozzleDistance:
            readNum('lidarNozzleDistance', 'lidar_nozzle_distance'),
        ultrasonicDistance:
            readNum('ultrasonicDistance', 'ultrasonic_distance'),
        wheelDiameter: readNum('wheelDiameter', 'wheel_diameter'),
        screwsInWheel: readInt('screwsInWheel', 'screws_per_wheel'),
        axleLength: readNum('axleLength', 'axle_length'),
        activeSessionId: json['active_session'] as int?,
        createdAt: parseTime('createdAt', 'created_at'),
        updatedAt: parseTime('updatedAt', 'updated_at'),
      );
    } else if (category == 'control_unit') {
      return ControlUnitModel(
        id: id,
        category: category,
        name: json['name'] as String? ?? '',
        userId: json['user'].toString() as String? ?? userId,
        status: json['status'] as String?,
        mountingHeight: readNum('mount_height_of_lidar', 'mounting_height'),
        lidarNozzleDistance: readNum(
            'distance_b_w_sensor_and_nozzle_center', 'lidar_nozzle_distance'),
        ultrasonicDistance: readNum(
            'distance_of_us_sensor_from_center_line', 'ultrasonic_distance'),
        wheelDiameter: readNum('wheelDiameter', 'wheel_diameter'),
        screwsInWheel: readInt('screwsInWheel', 'screws_per_wheel'),
        hingeToControlUnit:
            readNum('hingeToControlUnit', 'distance_hinge_control_unit'),
        macAddress:
            json['mac_addr'] as String? ?? json['mac_address'] as String?,
        linkedSprayerId: _extractId(json['sprayer']),
        linkedTractorId: _extractId(json['tractor']),
        linkedPlotId: _extractId(json['plot']),
        activeSessionId: json['active_session'] as int?,
        firmwareVersion: json['firmware_version'] as String?,
        firmwareAvailableVersion: json['firmware_available_version'] as String?,
        rightFrontOffset: readNum('right_front_offset', 'rightFrontOffset'),
        rightBackOffset: readNum('right_back_offset', 'rightBackOffset'),
        leftFrontOffset: readNum('left_front_offset', 'leftFrontOffset'),
        leftBackOffset: readNum('left_back_offset', 'leftBackOffset'),
        flowPulseCount: readNum('flow_pulse_count', 'flowPulseCount'),
        lastSeenAt: parseTime('last_seen_at', 'lastSeenAt'),
        createdAt: parseTime('createdAt', 'created_at'),
        updatedAt: parseTime('updatedAt', 'updated_at'),
      );
    } else {
      // default to SprayerModel
      return SprayerModel(
        id: id,
        category: category,
        name: json['name'] as String? ?? '',
        userId: userId,
        status: json['status'] as String?,
        activeSessionId: json['active_session'] as int?,
        mountingHeight: readNum('mountingHeight', 'mounting_height'),
        lidarNozzleDistance:
            readNum('lidarNozzleDistance', 'lidar_nozzle_distance'),
        ultrasonicDistance:
            readNum('ultrasonicDistance', 'ultrasonic_distance'),
        wheelDiameter: readNum('wheelDiameter', 'wheel_diameter'),
        screwsInWheel: readInt('screwsInWheel', 'screws_per_wheel'),
        axleLength: readNum('axleLength', 'axle_length'),
        nozzleCount: readInt('nozzleCount', 'nozzle_count'),
        tankCapacity: readNum('tankCapacity', 'tank_capacity'),
        hingeToAxle: readNum('hingeToAxle', 'distance_hinge_axle'),
        hingeToNozzle: readNum('hingeToNozzle', 'distance_hinge_nozzle'),
        hingeToControlUnit:
            readNum('hingeToControlUnit', 'distance_hinge_control_unit'),
        createdAt: parseTime('createdAt', 'created_at'),
        updatedAt: parseTime('updatedAt', 'updated_at'),
      );
    }
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'name': name,
        // canonical field
        'userId': userId,
        // keep legacy key for compatibility
        'ownerId': userId,
        'status': status,
        'activeSessionId': activeSessionId,
        'mountingHeight': mountingHeight,
        'lidarNozzleDistance': lidarNozzleDistance,
        'ultrasonicDistance': ultrasonicDistance,
        'wheelDiameter': wheelDiameter,
        'screwsInWheel': screwsInWheel,
        'axleLength': axleLength,
        'nozzleCount': nozzleCount,
        'tankCapacity': tankCapacity,
        'hingeToAxle': hingeToAxle,
        'hingeToNozzle': hingeToNozzle,
        'hingeToControlUnit': hingeToControlUnit,
        'macAddress': macAddress,
        'linkedSprayerId': linkedSprayerId,
        'linkedTractorId': linkedTractorId,
        'linkedPlotId': linkedPlotId,
        'rightFrontOffset': rightFrontOffset,
        'rightBackOffset': rightBackOffset,
        'leftFrontOffset': leftFrontOffset,
        'leftBackOffset': leftBackOffset,
        'flowPulseCount': flowPulseCount,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };
}

// Specific typed models for clarity and future specialization
class TractorModel extends EquipmentModel {
  TractorModel({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.mountingHeight,
    super.lidarNozzleDistance,
    super.ultrasonicDistance,
    super.wheelDiameter,
    super.screwsInWheel,
    super.axleLength,
    super.activeSessionId,
    super.createdAt,
    super.updatedAt,
  });
}

class SprayerModel extends EquipmentModel {
  SprayerModel({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.mountingHeight,
    super.lidarNozzleDistance,
    super.ultrasonicDistance,
    super.wheelDiameter,
    super.screwsInWheel,
    super.hingeToAxle,
    super.hingeToNozzle,
    super.hingeToControlUnit,
    super.axleLength,
    super.nozzleCount,
    super.tankCapacity,
    super.activeSessionId,
    super.createdAt,
    super.updatedAt,
  });
}

class ControlUnitModel extends EquipmentModel {
  ControlUnitModel({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.macAddress,
    super.linkedSprayerId,
    super.linkedTractorId,
    super.linkedPlotId,
    super.activeSessionId,
    super.lastSeenAt,
    super.firmwareVersion,
    super.firmwareAvailableVersion,
    super.mountingHeight,
    super.lidarNozzleDistance,
    super.ultrasonicDistance,
    super.wheelDiameter,
    super.screwsInWheel,
    super.hingeToControlUnit,
    super.rightFrontOffset,
    super.rightBackOffset,
    super.leftFrontOffset,
    super.leftBackOffset,
    super.flowPulseCount,
    super.createdAt,
    super.updatedAt,
  });
}
