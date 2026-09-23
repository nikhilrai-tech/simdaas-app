class EquipmentEntity {
  final String id;
  final String category; // e.g., tractor, sprayer
  final String name;
  final String? userId;
  final String? status; // e.g., 'vacant', 'assigned', 'in_service'

  // sprayer-specific fields
  final double? mountingHeight; // meters
  final double? lidarNozzleDistance; // meters
  final double?
      ultrasonicDistance; // meters from center line (for ultrasonic sensors)
  final double? wheelDiameter; // meters
  final int? screwsInWheel;
  // control unit specific
  // tractor-specific
  final double? axleLength;
  // sprayer nozzle / tank
  final int? nozzleCount;
  final double? tankCapacity; // liters
  // sprayer hinge distances
  final double? hingeToAxle;
  final double? hingeToNozzle;
  final double? hingeToControlUnit;
  // control unit specifics
  final String? macAddress;
  final String? linkedSprayerId;
  final String? linkedTractorId;
  final String? linkedPlotId;
  final int? activeSessionId;
  // Session ownership — control-unit only. 'server' = Automatic (the backend
  // infers sessions), 'device' = Manual (the sprayer starts/ends them).
  final String? sessionMode;
  // True once the hardware has sent a session-aware heartbeat, i.e. the
  // firmware can actually drive Manual mode.
  final bool? deviceSessionsSupported;
  // OTA firmware update (RFC-004) — control-unit only
  final String? firmwareVersion;
  final String? firmwareAvailableVersion;
  final double? rightFrontOffset;
  final double? rightBackOffset;
  final double? leftFrontOffset;
  final double? leftBackOffset;
  final double? flowPulseCount;
  // timestamps
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // legacy mounting/w lidar/ultrasonic kept for compatibility

  EquipmentEntity({
    required this.id,
    required this.category,
    required this.name,
    this.userId,
    this.status,
    this.mountingHeight,
    this.lidarNozzleDistance,
    this.ultrasonicDistance,
    this.wheelDiameter,
    this.screwsInWheel,
    this.axleLength,
    this.nozzleCount,
    this.tankCapacity,
    this.hingeToAxle,
    this.hingeToNozzle,
    this.hingeToControlUnit,
    this.macAddress,
    this.linkedSprayerId,
    this.linkedTractorId,
    this.linkedPlotId,
    this.activeSessionId,
    this.sessionMode,
    this.deviceSessionsSupported,
    this.firmwareVersion,
    this.firmwareAvailableVersion,
    this.rightFrontOffset,
    this.rightBackOffset,
    this.leftFrontOffset,
    this.leftBackOffset,
    this.flowPulseCount,
    this.lastSeenAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Manual mode: the sprayer owns the session (start/stop on the device or
  /// from the app); anything else is Automatic.
  bool get isManualSessionMode => sessionMode == 'device';
}

class TractorEntity extends EquipmentEntity {
  TractorEntity({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.wheelDiameter,
    super.screwsInWheel,
    super.axleLength,
  });
}

class SprayerEntity extends EquipmentEntity {
  SprayerEntity({
    required super.id,
    required super.category,
    required super.name,
    super.userId,
    super.status,
    super.mountingHeight,
    super.lidarNozzleDistance,
    super.ultrasonicDistance,
    super.hingeToAxle,
    super.hingeToNozzle,
    super.hingeToControlUnit,
    super.axleLength,
    super.nozzleCount,
    super.tankCapacity,
  });
}

class ControlUnitEntity extends EquipmentEntity {
  ControlUnitEntity({
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
    super.sessionMode,
    super.deviceSessionsSupported,
    super.lastSeenAt,
    super.firmwareVersion,
    super.firmwareAvailableVersion,
    super.lidarNozzleDistance,
    super.mountingHeight,
    super.ultrasonicDistance,
    super.rightFrontOffset,
    super.rightBackOffset,
    super.leftFrontOffset,
    super.leftBackOffset,
    super.flowPulseCount,
  });
}
